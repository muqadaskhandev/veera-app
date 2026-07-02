import Fluent
import Vapor

struct CreateInviteRequest: Content {
    var expiresInDays: Int?
    var clientEmail: String?
    var clientName: String?
    var clientPhone: String?
    var sessionsRemaining: Int?
    var age: Int?
    var gender: String?
    var heightCm: Int?
    var weightKg: Int?
    var injuryHistory: String?
    var primaryGoal: String?
    var skillLevel: String?
}

struct InviteCreatedResponse: Content {
    let invite: InviteCodeDTO
    let emailSent: Bool
    let client: ClientDTO?
}

enum ClientInviteEmailService {
    static func queueInvite(
        to email: String,
        trainerName: String,
        clientName: String?,
        code: String,
        expiresAt: Date?,
        on app: Application
    ) {
        TransactionalEmailService.queueClientInvite(
            to: email,
            trainerName: trainerName,
            clientName: clientName,
            code: code,
            expiresAt: expiresAt,
            on: app
        )
    }

    static func normalizeEmail(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else {
            throw Abort(.badRequest, reason: "Invalid client email address")
        }
        return trimmed
    }
}
