import Fluent
import Foundation
import Vapor

enum WorkoutService {
    private static let defaultDays: [WorkoutDayPayload] = [
        "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
    ].map { WorkoutDayPayload(id: nil, label: $0, focus: nil, exercises: []) }

    static func week(for clientID: UUID, weekIndex: Int, user: User, on database: any Database) async throws -> WorkoutWeekResponse {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)

        let weekCount = try await maxWeekCount(clientID: clientID, on: database)
        if let existing = try await WorkoutWeek.query(on: database)
            .filter(\.$client.$id == clientID)
            .filter(\.$weekIndex == weekIndex)
            .first() {
            let days = try decodeDays(existing.daysJSON)
            return WorkoutWeekResponse(weekIndex: weekIndex, weekCount: weekCount, days: days)
        }

        return WorkoutWeekResponse(weekIndex: weekIndex, weekCount: weekCount, days: defaultDays)
    }

    static func saveWeek(
        clientID: UUID,
        weekIndex: Int,
        payload: SaveWorkoutWeekRequest,
        user: User,
        on database: any Database
    ) async throws -> WorkoutWeekResponse {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)

        if let requestedCount = payload.weekCount {
            for index in 0..<max(1, requestedCount) where index != weekIndex {
                if try await WorkoutWeek.query(on: database)
                    .filter(\.$client.$id == clientID)
                    .filter(\.$weekIndex == index)
                    .first() == nil {
                    let blank = WorkoutWeek(clientID: clientID, weekIndex: index, daysJSON: try encodeDays(defaultDays))
                    try await blank.save(on: database)
                }
            }
        }

        let json = try encodeDays(payload.days)
        if let existing = try await WorkoutWeek.query(on: database)
            .filter(\.$client.$id == clientID)
            .filter(\.$weekIndex == weekIndex)
            .first() {
            existing.daysJSON = json
            try await existing.save(on: database)
        } else {
            let week = WorkoutWeek(clientID: clientID, weekIndex: weekIndex, daysJSON: json)
            try await week.save(on: database)
        }

        let weekCount = max(payload.weekCount ?? 1, try await maxWeekCount(clientID: clientID, on: database))
        return WorkoutWeekResponse(weekIndex: weekIndex, weekCount: weekCount, days: payload.days)
    }

    private static func maxWeekCount(clientID: UUID, on database: any Database) async throws -> Int {
        let weeks = try await WorkoutWeek.query(on: database)
            .filter(\.$client.$id == clientID)
            .all()
        return max(1, (weeks.map(\.weekIndex).max() ?? 0) + 1)
    }

    private static func encodeDays(_ days: [WorkoutDayPayload]) throws -> String {
        let data = try JSONEncoder().encode(days)
        guard let json = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Could not encode workout week")
        }
        return json
    }

    private static func decodeDays(_ json: String) throws -> [WorkoutDayPayload] {
        guard let data = json.data(using: .utf8) else { return defaultDays }
        return try JSONDecoder().decode([WorkoutDayPayload].self, from: data)
    }
}

enum ClientProfileService {
    static func weightLogs(clientID: UUID, user: User, on database: any Database) async throws -> [WeightLogDTO] {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
        return try await WeightLog.query(on: database)
            .filter(\.$client.$id == clientID)
            .sort(\.$recordedAt, .descending)
            .all()
            .map { try WeightLogDTO(from: $0) }
    }

    static func logWeight(
        clientID: UUID,
        payload: LogWeightRequest,
        user: User,
        on database: any Database,
        app: Application
    ) async throws -> WeightLogDTO {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
        let recordedAt = payload.recordedAt ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: recordedAt)

        if let existing = try await WeightLog.query(on: database)
            .filter(\.$client.$id == clientID)
            .filter(\.$recordedAt >= startOfDay)
            .first() {
            existing.kg = payload.kg
            existing.recordedAt = recordedAt
            try await existing.save(on: database)
            return try WeightLogDTO(from: existing)
        }

        let log = WeightLog(clientID: clientID, loggedByUserID: user.id, kg: payload.kg, recordedAt: recordedAt)
        try await log.save(on: database)

        if user.userRole == .client, let trainerID = try await Client.find(clientID, on: database)?.$trainer.id,
           let trainer = try await Trainer.find(trainerID, on: database),
           let trainerUserID = trainer.$user.id {
            await UserNotificationDeliveryService.deliver(
                to: trainerUserID,
                topic: .activity,
                category: "activity",
                title: "Weight logged",
                body: "A client logged a new weight entry.",
                pushKind: .activityAlert,
                on: database,
                app: app
            )
        }

        return try WeightLogDTO(from: log)
    }

    static func photos(clientID: UUID, user: User, on database: any Database, app: Application) async throws -> [ProgressPhotoDTO] {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
        let baseURL = Environment.get("APP_URL")
        return try await ProgressPhoto.query(on: database)
            .filter(\.$client.$id == clientID)
            .sort(\.$capturedAt, .descending)
            .all()
            .map { try ProgressPhotoDTO(from: $0, baseURL: baseURL) }
    }

    static func addPhoto(
        clientID: UUID,
        file: File,
        capturedAt: Date?,
        user: User,
        on database: any Database,
        app: Application
    ) async throws -> ProgressPhotoDTO {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)

        let data = Data(file.data.readableBytesView)
        guard !data.isEmpty else { throw Abort(.badRequest, reason: "Photo is empty") }

        let ext = (file.extension ?? "jpg").lowercased()
        let filename = "\(UUID().uuidString).\(ext)"
        let stored = try await StorageService.save(
            data: data,
            filename: filename,
            folder: "progress",
            contentType: file.contentType?.serialize() ?? "image/jpeg",
            on: app
        )

        let photo = ProgressPhoto(
            clientID: clientID,
            imagePath: stored,
            capturedAt: capturedAt ?? Date()
        )
        try await photo.save(on: database)
        return try ProgressPhotoDTO(from: photo, baseURL: Environment.get("APP_URL"))
    }

    static func deletePhoto(
        clientID: UUID,
        photoID: UUID,
        user: User,
        on database: any Database,
        app: Application
    ) async throws {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
        guard let photo = try await ProgressPhoto.query(on: database)
            .filter(\.$id == photoID)
            .filter(\.$client.$id == clientID)
            .first() else {
            throw Abort(.notFound, reason: "Photo not found")
        }

        let imagePath = photo.imagePath
        try await photo.delete(on: database)
        try? await StorageService.delete(storedPath: imagePath, on: app)
    }

    static func nutrition(clientID: UUID, user: User, on database: any Database) async throws -> NutritionProfileDTO {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)

        let profile = try await getOrCreateNutritionProfile(clientID: clientID, on: database)
        let notes = try await NutritionNote.query(on: database)
            .filter(\.$client.$id == clientID)
            .sort(\.$sortOrder, .ascending)
            .all()
        let supplements = try await Supplement.query(on: database)
            .filter(\.$client.$id == clientID)
            .sort(\.$sortOrder, .ascending)
            .all()

        return NutritionProfileDTO(
            proteinG: profile.proteinG,
            carbsG: profile.carbsG,
            fatsG: profile.fatsG,
            calories: profile.proteinG * 4 + profile.carbsG * 4 + profile.fatsG * 9,
            notes: try notes.map { try NutritionNoteDTO(from: $0) },
            supplements: try supplements.map { try SupplementDTO(from: $0) }
        )
    }

    static func updateNutrition(
        clientID: UUID,
        payload: UpdateNutritionRequest,
        user: User,
        on database: any Database
    ) async throws -> NutritionProfileDTO {
        _ = try await ClientAccessService.requireClient(clientID, for: user, on: database)
        let profile = try await getOrCreateNutritionProfile(clientID: clientID, on: database)

        if let proteinG = payload.proteinG { profile.proteinG = proteinG }
        if let carbsG = payload.carbsG { profile.carbsG = carbsG }
        if let fatsG = payload.fatsG { profile.fatsG = fatsG }
        try await profile.save(on: database)

        if let notes = payload.notes {
            try await NutritionNote.query(on: database).filter(\.$client.$id == clientID).delete()
            for (index, note) in notes.enumerated() {
                let row = NutritionNote(clientID: clientID, text: note.text, sortOrder: index)
                try await row.save(on: database)
            }
        }

        if let supplements = payload.supplements {
            try await Supplement.query(on: database).filter(\.$client.$id == clientID).delete()
            for (index, supplement) in supplements.enumerated() {
                let row = Supplement(clientID: clientID, name: supplement.name, dosage: supplement.dosage, sortOrder: index)
                try await row.save(on: database)
            }
        }

        return try await nutrition(clientID: clientID, user: user, on: database)
    }

    private static func getOrCreateNutritionProfile(clientID: UUID, on database: any Database) async throws -> NutritionProfile {
        if let existing = try await NutritionProfile.query(on: database)
            .filter(\.$client.$id == clientID)
            .first() {
            return existing
        }
        let profile = NutritionProfile(clientID: clientID, proteinG: 0, carbsG: 0, fatsG: 0)
        try await profile.save(on: database)
        return profile
    }
}
