import Fluent
import Vapor

final class InviteCode: Model, @unchecked Sendable {
    static let schema = "invite_codes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "code")
    var code: String

    @Parent(key: "trainer_id")
    var trainer: Trainer

    @OptionalParent(key: "created_by_user_id")
    var createdByUser: User?

    @OptionalParent(key: "redeemed_by_user_id")
    var redeemedByUser: User?

    @OptionalParent(key: "client_id")
    var client: Client?

    @OptionalField(key: "expires_at")
    var expiresAt: Date?

    @OptionalField(key: "redeemed_at")
    var redeemedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        code: String,
        trainerID: UUID,
        createdByUserID: UUID? = nil,
        expiresAt: Date? = nil
    ) {
        self.code = code
        self.$trainer.id = trainerID
        if let createdByUserID {
            self.$createdByUser.id = createdByUserID
        }
        self.expiresAt = expiresAt
    }

    var isRedeemable: Bool {
        redeemedAt == nil && (expiresAt == nil || expiresAt! > Date())
    }
}

struct InviteCodeDTO: Content {
    let id: UUID
    let code: String
    let trainerID: UUID
    let expiresAt: Date?
    let redeemedAt: Date?
    let isRedeemable: Bool

    init(from invite: InviteCode) throws {
        guard let id = invite.id else {
            throw Abort(.internalServerError, reason: "Invite missing id")
        }
        self.id = id
        self.code = invite.code
        self.trainerID = invite.$trainer.id
        self.expiresAt = invite.expiresAt
        self.redeemedAt = invite.redeemedAt
        self.isRedeemable = invite.isRedeemable
    }
}

struct ValidateInviteResponse: Content {
    let valid: Bool
    let trainerName: String?
    let trainerID: UUID?
    let message: String?
}
