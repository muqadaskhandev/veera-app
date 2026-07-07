import Fluent
import Vapor

final class Client: Model, @unchecked Sendable {
    static let schema = "clients"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "trainer_id")
    var trainer: Trainer

    @Field(key: "name")
    var name: String

    @Field(key: "initials")
    var initials: String

    @Field(key: "sessions_remaining")
    var sessionsRemaining: Int

    @Field(key: "days_left_on_plan")
    var daysLeftOnPlan: Int

    @Field(key: "status")
    var status: String

    @Field(key: "is_archived")
    var isArchived: Bool

    @Field(key: "email")
    var email: String

    @Field(key: "phone")
    var phone: String

    @OptionalField(key: "age")
    var age: Int?

    @Field(key: "gender")
    var gender: String

    @OptionalField(key: "height_cm")
    var heightCm: Int?

    @OptionalField(key: "weight_kg")
    var weightKg: Int?

    @OptionalField(key: "goal_weight_kg")
    var goalWeightKg: Int?

    @OptionalField(key: "start_weight_kg")
    var startWeightKg: Double?

    @Field(key: "injury_history")
    var injuryHistory: String

    @Field(key: "primary_goal")
    var primaryGoal: String

    @Field(key: "skill_level")
    var skillLevel: String

    @Field(key: "note")
    var note: String

    @OptionalField(key: "visible_modules_json")
    var visibleModulesJSON: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalParent(key: "user_id")
    var user: User?

    @Children(for: \.$client)
    var sessions: [Session]

    init() {}

    init(
        id: UUID? = nil,
        trainerID: UUID,
        name: String,
        initials: String,
        sessionsRemaining: Int,
        daysLeftOnPlan: Int = 30,
        status: String = "active",
        isArchived: Bool = false,
        email: String = "",
        phone: String = "",
        age: Int? = nil,
        gender: String = "",
        heightCm: Int? = nil,
        weightKg: Int? = nil,
        goalWeightKg: Int? = nil,
        injuryHistory: String = "",
        primaryGoal: String = "",
        skillLevel: String = "",
        note: String = ""
    ) {
        self.id = id
        self.$trainer.id = trainerID
        self.name = name
        self.initials = initials
        self.sessionsRemaining = sessionsRemaining
        self.daysLeftOnPlan = daysLeftOnPlan
        self.status = status
        self.isArchived = isArchived
        self.email = email
        self.phone = phone
        self.age = age
        self.gender = gender
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.goalWeightKg = goalWeightKg
        self.injuryHistory = injuryHistory
        self.primaryGoal = primaryGoal
        self.skillLevel = skillLevel
        self.note = note
    }
}

extension Client: Content {}

struct ClientDTO: Content {
    let id: UUID
    let trainerID: UUID
    let name: String
    let initials: String
    let sessionsRemaining: Int
    let daysLeftOnPlan: Int
    let status: String
    let isArchived: Bool
    let email: String
    let phone: String
    let age: Int?
    let gender: String
    let heightCm: Int?
    let weightKg: Int?
    let goalWeightKg: Int?
    let startWeightKg: Double?
    let injuryHistory: String
    let primaryGoal: String
    let skillLevel: String
    let note: String
    let visibleModules: [String]?
    let avatarURL: String?

    init(from client: Client, avatarURL: String? = nil) throws {
        guard let id = client.id else {
            throw Abort(.internalServerError, reason: "Client missing id")
        }
        self.id = id
        self.trainerID = client.$trainer.id
        self.name = client.name
        self.initials = client.initials
        self.sessionsRemaining = client.sessionsRemaining
        self.daysLeftOnPlan = client.daysLeftOnPlan
        self.status = client.status
        self.isArchived = client.isArchived
        self.email = client.email
        self.phone = client.phone
        self.age = client.age
        self.gender = client.gender
        self.heightCm = client.heightCm
        self.weightKg = client.weightKg
        self.goalWeightKg = client.goalWeightKg
        self.startWeightKg = client.startWeightKg
        self.injuryHistory = client.injuryHistory
        self.primaryGoal = client.primaryGoal
        self.skillLevel = client.skillLevel
        self.note = client.note
        self.visibleModules = ClientVisibleModules.decode(client.visibleModulesJSON)
        self.avatarURL = avatarURL
    }

    static func make(from client: Client, on database: any Database) async throws -> ClientDTO {
        var avatarURL: String?
        if let userID = client.$user.id {
            avatarURL = try await ProfileService.avatarURL(forUserID: userID, on: database)
        }
        return try ClientDTO(from: client, avatarURL: avatarURL)
    }
}

struct CreateClientRequest: Content {
    var name: String
    var initials: String?
    var sessionsRemaining: Int?
    var daysLeftOnPlan: Int?
    var status: String?
    var email: String?
    var phone: String?
    var age: Int?
    var gender: String?
    var heightCm: Int?
    var weightKg: Int?
    var goalWeightKg: Int?
    var startWeightKg: Double?
    var injuryHistory: String?
    var primaryGoal: String?
    var skillLevel: String?
    var note: String?
}

enum ClientVisibleModules {
    static let allowed: Set<String> = [
        "wearables", "workout", "nutrition", "weight", "photos", "financials",
    ]

    static func decode(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        let filtered = values.filter { allowed.contains($0) }
        return filtered.isEmpty ? nil : filtered
    }

    static func encode(_ values: [String]) -> String {
        let filtered = values.filter { allowed.contains($0) }
        let data = (try? JSONEncoder().encode(filtered)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func validated(_ values: [String]) throws -> [String] {
        let unknown = Set(values).subtracting(allowed)
        guard unknown.isEmpty else {
            throw Abort(.badRequest, reason: "Unknown profile module(s): \(unknown.sorted().joined(separator: ", "))")
        }
        return values.filter { allowed.contains($0) }
    }
}

struct UpdateClientRequest: Content {
    var name: String?
    var initials: String?
    var sessionsRemaining: Int?
    var daysLeftOnPlan: Int?
    var status: String?
    var isArchived: Bool?
    var email: String?
    var phone: String?
    var age: Int?
    var gender: String?
    var heightCm: Int?
    var weightKg: Int?
    var goalWeightKg: Int?
    var startWeightKg: Double?
    var injuryHistory: String?
    var primaryGoal: String?
    var skillLevel: String?
    var note: String?
    var visibleModules: [String]?
}
