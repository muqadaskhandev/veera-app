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

    /// Logs a ledger entry for sessions pre-filled when a client record is
    /// created (e.g. via an invite). Unlike `createEvent`, this does NOT touch
    /// `client.sessionsRemaining` — that balance was already set on the new
    /// `Client` row, so this only backfills the matching ledger entry so the
    /// "Packages" filter isn't empty for clients who started with a balance.
    static func recordInitialPackage(
        client: Client,
        trainerID: UUID,
        sessionsRemaining: Int,
        occurredAt: Date? = nil,
        on database: any Database
    ) async throws {
        guard sessionsRemaining > 0 else { return }
        let event = FinancialEvent(
            trainerID: trainerID,
            clientID: try client.requireID(),
            sessionID: nil,
            kind: "income",
            title: "Package Added",
            detail: "Starting session balance",
            amount: nil,
            sessionDelta: sessionsRemaining,
            occurredAt: occurredAt ?? client.createdAt ?? Date()
        )
        try await event.save(on: database)
    }

    static func createEvent(
        for user: User,
        payload: CreateFinancialEventRequest,
        on database: any Database,
        app: Application
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

        if user.userRole == .trainer || user.userRole == .admin {
            let category = payload.kind == "income" ? "payment" : "activity"
            await UserNotificationDeliveryService.deliver(
                to: user,
                topic: payload.kind == "income" ? .money : .activity,
                category: category,
                title: payload.title,
                body: payload.detail ?? payload.title,
                pushKind: payload.kind == "income" ? .paymentLogged : .activityAlert,
                on: database,
                app: app
            )
        }

        // Notify the client whenever sessions are credited (package or manual +).
        if delta > 0, let clientUserID = client.$user.id {
            let sessionLabel = delta == 1 ? "1 session" : "\(delta) sessions"
            var body = "Your trainer added \(sessionLabel) to your account."
            if let amount = payload.amount {
                body = "Your trainer added \(sessionLabel) (\(String(format: "$%.0f", amount)))."
            }
            await UserNotificationDeliveryService.deliver(
                to: clientUserID,
                topic: .activity,
                category: payload.kind == "income" ? "payment" : "activity",
                title: "Sessions added",
                body: body,
                pushKind: .paymentLogged,
                on: database,
                app: app
            )
        }

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
        let now = Date()

        switch filter.lowercased() {
        case "week":
            return (0..<7).reversed().map { back in
                let day = calendar.date(byAdding: .day, value: -back, to: now) ?? now
                let start = calendar.startOfDay(for: day)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                let slice = events.filter { $0.occurredAt >= start && $0.occurredAt < end }
                let label = day.formatted(.dateTime.weekday(.narrow))
                return FinancialBucketDTO(
                    label: label,
                    revenue: slice.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +),
                    sessions: slice.filter { $0.kind == "usage" }.count
                )
            }
        case "ytd":
            let year = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)
            return (1...currentMonth).map { month in
                let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                let slice = events.filter { $0.occurredAt >= start && $0.occurredAt < end }
                let label = start.formatted(.dateTime.month(.narrow))
                return FinancialBucketDTO(
                    label: label,
                    revenue: slice.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +),
                    sessions: slice.filter { $0.kind == "usage" }.count
                )
            }
        case "all":
            return (0..<6).reversed().map { back in
                let monthDate = calendar.date(byAdding: .month, value: -back, to: now) ?? now
                let comps = calendar.dateComponents([.year, .month], from: monthDate)
                let start = calendar.date(from: comps) ?? monthDate
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                let slice = events.filter { $0.occurredAt >= start && $0.occurredAt < end }
                let label = start.formatted(.dateTime.month(.narrow))
                return FinancialBucketDTO(
                    label: label,
                    revenue: slice.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +),
                    sessions: slice.filter { $0.kind == "usage" }.count
                )
            }
        default:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let monthStart = calendar.date(from: comps) ?? now
            return (0..<4).map { week in
                let start = calendar.date(byAdding: .day, value: week * 7, to: monthStart) ?? monthStart
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
                let slice = events.filter { $0.occurredAt >= start && $0.occurredAt < end }
                return FinancialBucketDTO(
                    label: "W\(week + 1)",
                    revenue: slice.filter { $0.kind == "income" }.compactMap(\.amount).reduce(0, +),
                    sessions: slice.filter { $0.kind == "usage" }.count
                )
            }
        }
    }
}

private extension DateInterval {
    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}
