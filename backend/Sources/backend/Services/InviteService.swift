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

    /// Creates a pending roster entry when a trainer invites someone who has not signed up yet.
    static func createPendingClient(
        for trainer: Trainer,
        payload: CreateInviteRequest,
        on database: any Database
    ) async throws -> Client? {
        let name = payload.clientName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        let email: String
        if let rawEmail = payload.clientEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rawEmail.isEmpty {
            email = try ClientInviteEmailService.normalizeEmail(rawEmail)
        } else {
            email = ""
        }

        let phone = payload.clientPhone?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let client = Client(
            trainerID: try trainer.requireID(),
            name: name,
            initials: initials(from: name),
            sessionsRemaining: payload.sessionsRemaining ?? 0,
            status: "pending",
            email: email,
            phone: phone,
            age: payload.age,
            gender: payload.gender ?? "",
            heightCm: payload.heightCm,
            weightKg: payload.weightKg,
            injuryHistory: payload.injuryHistory ?? "",
            primaryGoal: payload.primaryGoal ?? "",
            skillLevel: payload.skillLevel ?? ""
        )
        try await client.save(on: database)
        return client
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }

    static func invitedEmail(for invite: InviteCode, on database: any Database) async throws -> String? {
        if let stored = invite.invitedEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !stored.isEmpty {
            return stored
        }

        guard let clientID = invite.$client.id,
              let client = try await Client.find(clientID, on: database) else {
            return nil
        }
        let normalized = client.email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func assertSignupEmailMatchesInvite(
        signupEmail: String,
        inviteCode: String,
        on database: any Database
    ) async throws {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }

        guard let invite = try await InviteCode.query(on: database)
            .filter(\.$code == code)
            .first() else {
            throw Abort(.badRequest, reason: "Invite code not found")
        }

        guard invite.isRedeemable else {
            throw Abort(.badRequest, reason: "Invite code is no longer valid")
        }

        try await assertEmailMatchesInvite(
            userEmail: signupEmail,
            invite: invite,
            on: database
        )
    }

    static func emailMismatchMessage(invitedEmail: String) -> String {
        "This invite was sent to \(invitedEmail). Please sign up or sign in with that email address."
    }

    static func assertEmailMatchesInvite(
        userEmail: String?,
        invite: InviteCode,
        on database: any Database
    ) async throws {
        guard let invitedEmail = try await invitedEmail(for: invite, on: database) else {
            return
        }

        let normalizedUserEmail = userEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        guard !normalizedUserEmail.isEmpty else {
            throw Abort(.badRequest, reason: emailMismatchMessage(invitedEmail: invitedEmail))
        }

        guard normalizedUserEmail == invitedEmail else {
            throw Abort(.badRequest, reason: emailMismatchMessage(invitedEmail: invitedEmail))
        }
    }

    static func validate(code: String, on database: any Database) async throws -> ValidateInviteResponse {
        let normalized = code.uppercased()
        guard let invite = try await InviteCode.query(on: database)
            .filter(\.$code == normalized)
            .with(\.$trainer)
            .first() else {
            return ValidateInviteResponse(
                valid: false,
                trainerName: nil,
                trainerID: nil,
                invitedEmail: nil,
                message: "Invite code not found"
            )
        }

        guard invite.isRedeemable else {
            return ValidateInviteResponse(
                valid: false,
                trainerName: nil,
                trainerID: nil,
                invitedEmail: nil,
                message: "Invite code is no longer valid"
            )
        }

        let trainer = try await invite.$trainer.get(on: database)
        let invitedEmail = try await invitedEmail(for: invite, on: database)
        return ValidateInviteResponse(
            valid: true,
            trainerName: trainer.name,
            trainerID: trainer.id,
            invitedEmail: invitedEmail,
            message: nil
        )
    }

    /// Links a signed-in client to their coach using an invite code (during or after onboarding).
    static func redeem(code rawCode: String, for user: User, on database: any Database) async throws -> ProfileResponse {
        guard user.userRole == .client else {
            throw Abort(.forbidden, reason: "Only clients can redeem invite codes")
        }

        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            throw Abort(.badRequest, reason: "Invite code is required")
        }

        guard let invite = try await InviteCode.query(on: database)
            .filter(\.$code == code)
            .with(\.$trainer)
            .first() else {
            throw Abort(.badRequest, reason: "Invite code not found")
        }

        let userID = try user.requireID()
        let trainer = try await invite.$trainer.get(on: database)
        let trainerID = try trainer.requireID()

        if let redeemedBy = invite.$redeemedByUser.id {
            if redeemedBy == userID {
                return try await ProfileService.load(for: user, on: database)
            }
            throw Abort(.badRequest, reason: "This invite code has already been used")
        }

        guard invite.isRedeemable else {
            throw Abort(.badRequest, reason: "Invite code is no longer valid")
        }

        try await assertEmailMatchesInvite(userEmail: user.email, invite: invite, on: database)

        if let priorInvite = try await InviteCode.query(on: database)
            .filter(\.$redeemedByUser.$id == userID)
            .first(),
           priorInvite.$trainer.id != trainerID {
            throw Abort(.conflict, reason: "You're already connected to a trainer")
        }

        if let existing = try await Client.query(on: database)
            .filter(\.$user.$id == userID)
            .first() {
            if existing.$trainer.id == trainerID {
                try await markInviteRedeemed(invite, userID: userID, clientID: try existing.requireID(), on: database)
                return try await ProfileService.load(for: user, on: database)
            }

            if try await InviteCode.query(on: database)
                .filter(\.$redeemedByUser.$id == userID)
                .first() != nil {
                throw Abort(.conflict, reason: "You're already connected to a trainer")
            }

            existing.$trainer.id = trainerID
            if existing.status == "pending" || existing.sessionsRemaining == 0 {
                existing.status = "active"
            }
            if existing.email.isEmpty, let email = user.email {
                existing.email = email
            }
            try await existing.save(on: database)
            try await markInviteRedeemed(invite, userID: userID, clientID: try existing.requireID(), on: database)
            return try await ProfileService.load(for: user, on: database)
        }

        try await AuthService.linkClientToInvite(
            user: user,
            inviteCode: code,
            displayName: user.displayName,
            primaryGoal: "",
            on: database
        )
        return try await ProfileService.load(for: user, on: database)
    }

    private static func markInviteRedeemed(
        _ invite: InviteCode,
        userID: UUID,
        clientID: UUID,
        on database: any Database
    ) async throws {
        invite.redeemedAt = Date()
        invite.$redeemedByUser.id = userID
        invite.$client.id = clientID
        try await invite.save(on: database)
    }
}
