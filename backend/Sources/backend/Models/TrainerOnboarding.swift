import Fluent
import Vapor

final class TrainerOnboarding: Model, @unchecked Sendable {
    static let schema = "trainer_onboarding"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "answers_json")
    var answersJSON: String

    @OptionalField(key: "completed_at")
    var completedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: UUID, answersJSON: String, completedAt: Date? = nil) {
        self.$user.id = userID
        self.answersJSON = answersJSON
        self.completedAt = completedAt
    }
}

struct TrainerOnboardingDTO: Content {
    let completed: Bool
    let answers: [String: String]
    let completedAt: Date?

    init(from onboarding: TrainerOnboarding) throws {
        let data = onboarding.answersJSON.data(using: .utf8) ?? Data("{}".utf8)
        let answers = try JSONDecoder().decode([String: String].self, from: data)
        self.completed = onboarding.completedAt != nil
        self.answers = answers
        self.completedAt = onboarding.completedAt
    }
}

struct SaveTrainerOnboardingRequest: Content {
    var answers: [String: String]
    var markComplete: Bool?
}

struct ClientOnboardingRequest: Content {
    var inviteCode: String?
    var displayName: String?
    var primaryGoal: String?
}

struct OnboardingStatusResponse: Content {
    let role: String
    let onboarded: Bool
    let details: OnboardingDetails?

    struct OnboardingDetails: Content {
        let trainerOnboarding: TrainerOnboardingDTO?
        let linkedTrainerID: UUID?
        let linkedClientID: UUID?
    }
}
