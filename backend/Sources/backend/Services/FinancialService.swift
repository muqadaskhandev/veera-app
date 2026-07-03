import Fluent
import Foundation
import Vapor

enum FinancialService {
    static func summary(for user: User, filter: String, on database: any Database) async throws -> FinancialSummaryDTO {
        var query = FinancialEvent.query(on: database).sort(\.$occurredAt, .descending)
        if user.userRole != .admin {
            let trainer = try await ClientAccessService.trainer(for: user, on: database)
            let trainerID = try trainer.requireID()
            query = query.filter(\.$trainer.$id == trainerID)
        }
        let events = try await query.all()

        let window = timeWindow(for: filter)
        let filtered = events.filter { window.contains($0.occurredAt) }

        var clientNames: [UUID: String] = [:]
        var dtos: [FinancialEventDTO] = []
        for event in filtered {
            let name: String?
            if let clientID = event.$client.id {
                if let cached = clientNames[clientID] {
                    name = cached
                } else if let client = try await Client.find(clientID, on: database) {
                    clientNames[clientID] = client.name
                    name = client.name
                } else {
                    name = nil
                }
            } else {
                name = nil
            }
            dtos.append(try FinancialEventDTO(from: event, clientName: name))
        }

        let revenue = filtered.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +)
        let sessionsUsed = filtered.filter { $0.kind == "usage" }.count
        let buckets = makeBuckets(from: filtered, filter: filter)

        return FinancialSummaryDTO(revenue: revenue, sessionsUsed: sessionsUsed, events: dtos, buckets: buckets)
    }

    static func clientLedger(clientID: UUID, for user: User, on database: any Database) async throws -> [FinancialEventDTO] {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
        let events = try await FinancialEvent.query(on: database)
            .filter(\.$client.$id == clientID)
            .sort(\.$occurredAt, .descending)
            .all()

        let client = try await Client.find(clientID, on: database)
        let name = client?.name
        return try events.map { try FinancialEventDTO(from: $0, clientName: name) }
    }

    static func createEvent(
        for user: User,
        payload: CreateFinancialEventRequest,
        on database: any Database
    ) async throws -> FinancialEventDTO {
        let client = try await ClientAccessService.requireClient(payload.clientID, for: user, on: database)
        let trainer: Trainer
        if user.userRole == .admin {
            trainer = try await ClientAccessService.trainerForClient(payload.clientID, on: database)
        } else {
            trainer = try await ClientAccessService.trainer(for: user, on: database)
        }

        let delta = payload.sessionDelta ?? 0
        if delta != 0 {
            client.sessionsRemaining = max(0, client.sessionsRemaining + delta)
            try await client.save(on: database)
        }

        let event = FinancialEvent(
            trainerID: try trainer.requireID(),
            clientID: payload.clientID,
            sessionID: nil,
            kind: payload.kind,
            title: payload.title,
            detail: payload.detail ?? payload.title,
            amount: payload.amount,
            sessionDelta: delta,
            occurredAt: payload.occurredAt ?? Date()
        )
        try await event.save(on: database)
        return try FinancialEventDTO(from: event, clientName: client.name)
    }

    private static func timeWindow(for filter: String) -> DateInterval {
        let now = Date()
        let calendar = Calendar.current
        switch filter.lowercased() {
        case "week":
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return DateInterval(start: start, end: now)
        case "ytd":
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            return DateInterval(start: start, end: now)
        case "all":
            return DateInterval(start: .distantPast, end: now)
        default:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return DateInterval(start: start, end: now)
        }
    }

    private static func makeBuckets(from events: [FinancialEvent], filter: String) -> [FinancialBucketDTO] {
        let calendar = Calendar.current
        switch filter.lowercased() {
        case "week":
            let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            return labels.enumerated().map { index, label in
                let dayEvents = events.filter {
                    calendar.component(.weekday, from: $0.occurredAt) == index + 1
                }
                return FinancialBucketDTO(
                    label: label,
                    revenue: dayEvents.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +),
                    sessions: dayEvents.filter { $0.kind == "usage" }.count
                )
            }
        default:
            return [
                FinancialBucketDTO(
                    label: filter.capitalized,
                    revenue: events.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +),
                    sessions: events.filter { $0.kind == "usage" }.count
                ),
            ]
        }
    }
}

private extension DateInterval {
    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}
