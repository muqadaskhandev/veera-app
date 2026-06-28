import Crypto
import Fluent
import Vapor

enum InviteService {
    static func generateCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    static func createInvite(
        for trainer: Trainer,
        createdBy user: User,
        expiresInDays: Int?,
        on database: any Database
    ) async throws -> InviteCode {
        var code = generateCode()
        while try await InviteCode.query(on: database).filter(\.$code == code).first() != nil {
            code = generateCode()
        }

        let expiresAt = expiresInDays.map { Date().addingTimeInterval(TimeInterval($0 * 24 * 60 * 60)) }
        let invite = InviteCode(
            code: code,
            trainerID: try trainer.requireID(),
            createdByUserID: try user.requireID(),
            expiresAt: expiresAt
        )
        try await invite.save(on: database)
        return invite
    }

    static func validate(code: String, on database: any Database) async throws -> ValidateInviteResponse {
        let normalized = code.uppercased()
        guard let invite = try await InviteCode.query(on: database)
            .filter(\.$code == normalized)
            .with(\.$trainer)
            .first() else {
            return ValidateInviteResponse(valid: false, trainerName: nil, trainerID: nil, message: "Invite code not found")
        }

        guard invite.isRedeemable else {
            return ValidateInviteResponse(valid: false, trainerName: nil, trainerID: nil, message: "Invite code is no longer valid")
        }

        let trainer = try await invite.$trainer.get(on: database)
        return ValidateInviteResponse(
            valid: true,
            trainerName: trainer.name,
            trainerID: trainer.id,
            message: nil
        )
    }
}
