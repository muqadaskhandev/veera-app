import Fluent
import Vapor

enum AccountService {
    static func changePassword(
        for user: User,
        currentPassword: String,
        newPassword: String,
        on database: any Database
    ) async throws {
        guard let passwordHash = user.passwordHash else {
            throw Abort(.badRequest, reason: "This account uses Sign in with Apple or Google and does not have a password")
        }
        guard try Bcrypt.verify(currentPassword, created: passwordHash) else {
            throw Abort(.unauthorized, reason: "Current password is incorrect")
        }
        guard newPassword.count >= 8 else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters")
        }
        user.passwordHash = try Bcrypt.hash(newPassword)
        try await user.save(on: database)
    }

    static func deleteAccount(for user: User, on database: any Database) async throws {
        guard let userID = user.id else { throw Abort(.internalServerError) }
        if user.role == UserRole.admin.rawValue {
            let adminCount = try await User.query(on: database)
                .filter(\.$role == UserRole.admin.rawValue)
                .count()
            if adminCount <= 1 {
                throw Abort(.badRequest, reason: "Cannot delete the last admin account")
            }
        }
        try await UserDeletionService.purge(user, on: database)
        _ = userID
    }

    static func submitSupportTicket(
        for user: User,
        topic: String,
        message: String,
        attachment: File?,
        on database: any Database,
        app: Application
    ) async throws -> SupportTicketDTO {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else {
            throw Abort(.badRequest, reason: "Topic is required")
        }
        guard !trimmedMessage.isEmpty else {
            throw Abort(.badRequest, reason: "Message is required")
        }

        var attachmentPath: String?
        if let attachment, !attachment.filename.isEmpty {
            let data = Data(attachment.data.readableBytesView)
            let filename = "\(UUID().uuidString)-\(attachment.filename)"
            attachmentPath = try await StorageService.save(
                data: data,
                filename: filename,
                folder: "support",
                contentType: attachment.contentType?.serialize() ?? "application/octet-stream",
                on: app
            )
        }

        let ticket = SupportTicket(
            userID: try user.requireID(),
            topic: trimmedTopic,
            message: trimmedMessage,
            attachmentPath: attachmentPath
        )
        try await ticket.save(on: database)
        return try SupportTicketDTO(from: ticket)
    }
}

enum UserDeletionService {
    static func purge(_ user: User, on database: any Database) async throws {
        guard let userID = user.id else { return }

        try await AuthSession.query(on: database).filter(\.$user.$id == userID).delete()
        try await PushDeviceToken.query(on: database).filter(\.$user.$id == userID).delete()
        try await UserNotification.query(on: database).filter(\.$user.$id == userID).delete()
        try await NotificationPreferences.query(on: database).filter(\.$user.$id == userID).delete()
        try await NotificationOutbox.query(on: database).filter(\.$user.$id == userID).delete()
        try await Subscription.query(on: database).filter(\.$user.$id == userID).delete()
        try await SupportTicket.query(on: database).filter(\.$user.$id == userID).delete()
        try await StripePayment.query(on: database).filter(\.$user.$id == userID).delete()

        if let trainer = try await Trainer.query(on: database).filter(\.$user.$id == userID).first() {
            let trainerID = try trainer.requireID()
            try await FinancialEvent.query(on: database).filter(\.$trainer.$id == trainerID).delete()
            try await InviteCode.query(on: database).filter(\.$trainer.$id == trainerID).delete()
            if let trainerUserID = trainer.$user.id {
                try await TrainerOnboarding.query(on: database).filter(\.$user.$id == trainerUserID).delete()
            }
            try await trainer.delete(on: database)
        }

        if let client = try await Client.query(on: database).filter(\.$user.$id == userID).first() {
            try await ClientDeletionService.delete(client, on: database)
        }

        try await Profile.query(on: database).filter(\.$user.$id == userID).delete()
        try await user.delete(on: database)
    }
}
