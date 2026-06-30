import Fluent
import Vapor

enum HealthService {
    static func sync(for user: User, payload: HealthSyncRequest, on database: any Database) async throws -> HealthMeResponse {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        guard WearableProvider(rawValue: payload.provider) != nil else {
            throw Abort(.badRequest, reason: "Unknown provider: \(payload.provider)")
        }

        let now = Date()
        if let existing = try await WearableConnection.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$provider == payload.provider)
            .first() {
            existing.lastSyncedAt = now
            try await existing.save(on: database)
        } else {
            let connection = WearableConnection(
                userID: userID,
                provider: payload.provider,
                connectedAt: now,
                lastSyncedAt: now
            )
            try await connection.save(on: database)
        }

        for input in payload.metrics {
            let day = HealthDateCodec.startOfDayUTC(try HealthDateCodec.parseDay(input.date))
            let metric = try await HealthDailyMetric.query(on: database)
                .filter(\.$user.$id == userID)
                .filter(\.$date == day)
                .first()

            if let metric {
                apply(input, to: metric, source: payload.provider)
                try await metric.save(on: database)
            } else {
                let created = HealthDailyMetric(
                    userID: userID,
                    date: day,
                    sleepMinutes: input.sleepMinutes,
                    steps: input.steps,
                    restingHR: input.restingHR,
                    hrv: input.hrv,
                    activeCalories: input.activeCalories,
                    source: payload.provider
                )
                try await created.save(on: database)
            }
        }

        return try await metrics(for: user, on: database)
    }

    static func connect(for user: User, provider: String, on database: any Database) async throws -> WearableConnectionDTO {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        guard WearableProvider(rawValue: provider) != nil else {
            throw Abort(.badRequest, reason: "Unknown provider: \(provider)")
        }
        if provider == WearableProvider.oura.rawValue {
            throw Abort(.badRequest, reason: "Connect Oura through the OAuth flow")
        }

        if let existing = try await WearableConnection.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$provider == provider)
            .first() {
            return WearableConnectionDTO(from: existing)
        }

        let connection = WearableConnection(userID: userID, provider: provider)
        try await connection.save(on: database)
        return WearableConnectionDTO(from: connection)
    }

    static func disconnect(for user: User, provider: String, on database: any Database) async throws -> HTTPStatus {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }
        if provider == WearableProvider.oura.rawValue {
            try await OuraService.revoke(for: userID, on: database)
        }
        try await WearableConnection.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$provider == provider)
            .delete()
        return .noContent
    }

    static func metrics(for user: User, days: Int = 30, on database: any Database) async throws -> HealthMeResponse {
        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User missing id")
        }

        let since = HealthDateCodec.daysAgo(days)
        let connections = try await WearableConnection.query(on: database)
            .filter(\.$user.$id == userID)
            .all()
            .map(WearableConnectionDTO.init)

        let metrics = try await HealthDailyMetric.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$date >= since)
            .sort(\.$date, .ascending)
            .all()
            .map(HealthDailyMetricDTO.init)

        return HealthMeResponse(connections: connections, metrics: metrics)
    }

    static func metricsForClient(
        clientID: UUID,
        requestedBy user: User,
        days: Int = 30,
        on database: any Database
    ) async throws -> HealthMeResponse {
        guard let client = try await Client.find(clientID, on: database) else {
            throw Abort(.notFound, reason: "Client not found")
        }
        try await authorizeClientAccess(client: client, user: user, on: database)

        guard let clientUserID = client.$user.id else {
            return HealthMeResponse(connections: [], metrics: [])
        }

        let since = HealthDateCodec.daysAgo(days)
        let connections = try await WearableConnection.query(on: database)
            .filter(\.$user.$id == clientUserID)
            .all()
            .map(WearableConnectionDTO.init)

        let metrics = try await HealthDailyMetric.query(on: database)
            .filter(\.$user.$id == clientUserID)
            .filter(\.$date >= since)
            .sort(\.$date, .ascending)
            .all()
            .map(HealthDailyMetricDTO.init)

        return HealthMeResponse(connections: connections, metrics: metrics)
    }

    private static func authorizeClientAccess(client: Client, user: User, on database: any Database) async throws {
        guard let role = user.userRole else {
            throw Abort(.forbidden, reason: "Insufficient permissions")
        }

        switch role {
        case .admin:
            return
        case .client:
            guard client.$user.id == user.id else {
                throw Abort(.forbidden, reason: "You can only view your own health data")
            }
        case .trainer:
            guard let trainer = try await Trainer.query(on: database)
                .filter(\.$user.$id == user.id!)
                .first(),
                trainer.id == client.$trainer.id else {
                throw Abort(.forbidden, reason: "You can only view health data for your clients")
            }
        }
    }

    private static func apply(_ input: HealthDailyMetricInput, to metric: HealthDailyMetric, source: String) {
        guard let provider = HealthMetricMerge.provider(from: source) else {
            applyWithoutPrecedence(input, to: metric, source: source)
            return
        }

        if HealthMetricMerge.shouldApply(field: .sleepMinutes, provider: provider, existing: metric.sleepMinutes, incoming: input.sleepMinutes),
           let sleepMinutes = input.sleepMinutes {
            metric.sleepMinutes = sleepMinutes
        }
        if HealthMetricMerge.shouldApply(field: .steps, provider: provider, existing: metric.steps, incoming: input.steps),
           let steps = input.steps {
            metric.steps = steps
        }
        if HealthMetricMerge.shouldApply(field: .restingHR, provider: provider, existing: metric.restingHR, incoming: input.restingHR),
           let restingHR = input.restingHR {
            metric.restingHR = restingHR
        }
        if HealthMetricMerge.shouldApply(field: .hrv, provider: provider, existing: metric.hrv, incoming: input.hrv),
           let hrv = input.hrv {
            metric.hrv = hrv
        }
        if HealthMetricMerge.shouldApply(field: .activeCalories, provider: provider, existing: metric.activeCalories, incoming: input.activeCalories),
           let activeCalories = input.activeCalories {
            metric.activeCalories = activeCalories
        }

        metric.source = HealthMetricMerge.mergedSource(existing: metric.source, incoming: source)
    }

    private static func applyWithoutPrecedence(_ input: HealthDailyMetricInput, to metric: HealthDailyMetric, source: String) {
        if let sleepMinutes = input.sleepMinutes { metric.sleepMinutes = sleepMinutes }
        if let steps = input.steps { metric.steps = steps }
        if let restingHR = input.restingHR { metric.restingHR = restingHR }
        if let hrv = input.hrv { metric.hrv = hrv }
        if let activeCalories = input.activeCalories { metric.activeCalories = activeCalories }
        metric.source = source
    }
}
