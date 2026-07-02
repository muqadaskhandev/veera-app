import Foundation

struct AuthUserDTO: Codable {
    let id: UUID
    let email: String?
    let role: String
    let displayName: String
}

struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUserDTO
}

struct ValidateInviteResponse: Codable {
    let valid: Bool
    let trainerName: String?
    let trainerID: UUID?
    let invitedEmail: String?
    let message: String?
}

struct RedeemInviteResponse: Codable {
    let message: String
    let trainerName: String
    let profile: ProfileResponse
}

struct TrainerOnboardingResponse: Codable {
    let completed: Bool
    let answers: [String: String]
    let completedAt: Date?
}

struct RegisterResponse: Codable {
    let requiresEmailVerification: Bool
    let email: String
    let message: String
    let devCode: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: AuthUserDTO?
}

struct ResendVerificationResponse: Codable {
    let message: String
    let retryAfterSeconds: Int?
    let alreadyVerified: Bool?
}

struct PasswordResetRequestedResponse: Codable {
    let message: String
    let retryAfterSeconds: Int?
}

struct MessageResponse: Codable {
    let message: String
}

enum VerraAPI {
    struct RegisterBody: Encodable {
        let email: String
        let password: String
        let role: String
        let displayName: String
        let inviteCode: String?
    }

    struct SaveTrainerOnboardingBody: Encodable {
        let answers: [String: String]
        let markComplete: Bool
    }

    struct ValidateInviteBody: Encodable {
        let code: String
    }

    struct VerifyEmailBody: Encodable {
        let email: String
        let code: String
    }

    struct ResendVerificationBody: Encodable {
        let email: String
    }

    struct LoginBody: Encodable {
        let email: String
        let password: String
    }

    static func login(email: String, password: String) async throws -> AuthTokenResponse {
        try await APIClient.shared.request(
            "/api/auth/login",
            method: "POST",
            body: LoginBody(
                email: email,
                password: password
            )
        )
    }

    struct ForgotPasswordBody: Encodable {
        let email: String
    }

    struct ResetPasswordBody: Encodable {
        let email: String
        let code: String
        let newPassword: String
    }

    static func requestPasswordReset(email: String) async throws -> PasswordResetRequestedResponse {
        try await APIClient.shared.request(
            "/api/auth/password/forgot",
            method: "POST",
            body: ForgotPasswordBody(email: email)
        )
    }

    static func resetPassword(email: String, code: String, newPassword: String) async throws -> MessageResponse {
        try await APIClient.shared.request(
            "/api/auth/password/reset",
            method: "POST",
            body: ResetPasswordBody(email: email, code: code, newPassword: newPassword)
        )
    }

    static func registerTrainer(email: String, password: String, displayName: String) async throws -> RegisterResponse {
        try await APIClient.shared.request(
            "/api/auth/register",
            method: "POST",
            body: RegisterBody(
                email: email,
                password: password,
                role: "trainer",
                displayName: displayName,
                inviteCode: nil
            )
        )
    }

    static func registerClient(
        email: String,
        password: String,
        displayName: String,
        inviteCode: String?
    ) async throws -> RegisterResponse {
        try await APIClient.shared.request(
            "/api/auth/register",
            method: "POST",
            body: RegisterBody(
                email: email,
                password: password,
                role: "client",
                displayName: displayName,
                inviteCode: inviteCode
            )
        )
    }

    static func verifyEmail(email: String, code: String) async throws -> AuthTokenResponse {
        try await APIClient.shared.request(
            "/api/auth/verify-email",
            method: "POST",
            body: VerifyEmailBody(email: email, code: code)
        )
    }

    static func resendVerificationEmail(email: String) async throws -> ResendVerificationResponse {
        try await APIClient.shared.request(
            "/api/auth/verify-email/resend",
            method: "POST",
            body: ResendVerificationBody(email: email)
        )
    }

    static func validateInvite(code: String) async throws -> ValidateInviteResponse {
        try await APIClient.shared.request(
            "/api/onboarding/invite/validate",
            method: "POST",
            body: ValidateInviteBody(code: code)
        )
    }

    static func redeemInvite(code: String, accessToken: String) async throws -> RedeemInviteResponse {
        try await APIClient.shared.request(
            "/api/onboarding/client/invite",
            method: "POST",
            body: ValidateInviteBody(code: code),
            token: accessToken
        )
    }

    static func saveTrainerOnboarding(
        answers: [String: String],
        accessToken: String
    ) async throws -> TrainerOnboardingResponse {
        try await APIClient.shared.request(
            "/api/onboarding/trainer",
            method: "POST",
            body: SaveTrainerOnboardingBody(answers: answers, markComplete: true),
            token: accessToken
        )
    }

    struct AppleSignInBody: Encodable {
        let identityToken: String
        let role: String
        let displayName: String?
        let inviteCode: String?
    }

    static func signInWithApple(
        identityToken: String,
        role: OnboardingRole,
        displayName: String?,
        inviteCode: String?
    ) async throws -> AuthTokenResponse {
        try await APIClient.shared.request(
            "/api/auth/apple",
            method: "POST",
            body: AppleSignInBody(
                identityToken: identityToken,
                role: role == .trainer ? "trainer" : "client",
                displayName: displayName,
                inviteCode: inviteCode
            )
        )
    }

    struct RefreshBody: Encodable {
        let refreshToken: String
    }

    static func me(accessToken: String) async throws -> AuthUserDTO {
        try await APIClient.shared.request("/api/auth/me", token: accessToken)
    }

    static func refresh(refreshToken: String) async throws -> AuthTokenResponse {
        try await APIClient.shared.request(
            "/api/auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: refreshToken)
        )
    }

    static func fetchProfile(accessToken: String) async throws -> ProfileResponse {
        try await APIClient.shared.request("/api/profile/me", token: accessToken)
    }

    static func updateProfile(accessToken: String, body: UpdateProfileBody) async throws -> ProfileResponse {
        try await APIClient.shared.request(
            "/api/profile/me",
            method: "PATCH",
            body: body,
            token: accessToken
        )
    }

    static func uploadAvatar(
        imageData: Data,
        filename: String,
        mimeType: String,
        accessToken: String
    ) async throws -> ProfileResponse {
        try await APIClient.shared.upload(
            path: "/api/profile/avatar",
            fieldName: "avatar",
            fileData: imageData,
            filename: filename,
            mimeType: mimeType,
            token: accessToken
        )
    }

    static func syncHealth(
        provider: String,
        metrics: [HealthDailyMetricInput],
        accessToken: String
    ) async throws -> HealthMeResponse {
        try await APIClient.shared.request(
            "/api/health/sync",
            method: "POST",
            body: HealthSyncBody(provider: provider, metrics: metrics),
            token: accessToken
        )
    }

    static func fetchMyHealth(accessToken: String, days: Int = 30) async throws -> HealthMeResponse {
        try await APIClient.shared.request(
            "/api/health/me?days=\(days)",
            token: accessToken
        )
    }

    static func fetchClientHealth(clientID: UUID, accessToken: String, days: Int = 30) async throws -> HealthMeResponse {
        try await APIClient.shared.request(
            "/api/clients/\(clientID.uuidString)/health?days=\(days)",
            token: accessToken
        )
    }

    static func connectHealthProvider(provider: String, accessToken: String) async throws -> WearableConnectionDTO {
        try await APIClient.shared.request(
            "/api/health/connect",
            method: "POST",
            body: HealthConnectBody(provider: provider),
            token: accessToken
        )
    }

    static func disconnectHealthProvider(provider: String, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/health/connect/\(provider)",
            method: "DELETE",
            token: accessToken
        )
    }

    static func fetchOuraAuthorize(accessToken: String) async throws -> OuraAuthorizeResponse {
        try await APIClient.shared.request("/api/health/oura/authorize", token: accessToken)
    }

    struct OuraCallbackBody: Encodable {
        let code: String
        let state: String
    }

    static func completeOuraOAuth(code: String, state: String, accessToken: String) async throws -> WearableConnectionDTO {
        try await APIClient.shared.request(
            "/api/health/oura/callback",
            method: "POST",
            body: OuraCallbackBody(code: code, state: state),
            token: accessToken
        )
    }

    static func syncOura(accessToken: String, days: Int = 30) async throws -> HealthMeResponse {
        try await APIClient.shared.request(
            "/api/health/oura/sync?days=\(days)",
            method: "POST",
            token: accessToken
        )
    }

    struct CreateInviteBody: Encodable {
        let expiresInDays: Int?
        let clientEmail: String?
        let clientName: String?
        let clientPhone: String?
        let sessionsRemaining: Int?
        let age: Int?
        let gender: String?
        let heightCm: Int?
        let weightKg: Int?
        let injuryHistory: String?
        let primaryGoal: String?
        let skillLevel: String?
    }

    struct InviteCreatedResponse: Decodable {
        let invite: InviteCodeDTO
        let emailSent: Bool
        let client: ClientDTO?
    }

    struct InviteCodeDTO: Decodable {
        let id: UUID
        let code: String
        let trainerID: UUID
        let expiresAt: Date?
        let redeemedAt: Date?
        let isRedeemable: Bool
    }

    static func fetchClients(accessToken: String, archived: Bool = false) async throws -> [ClientDTO] {
        try await APIClient.shared.request(
            "/api/clients?archived=\(archived)",
            token: accessToken
        )
    }

    static func createInvite(
        clientEmail: String?,
        clientName: String?,
        clientPhone: String? = nil,
        sessionsRemaining: Int? = nil,
        age: Int? = nil,
        gender: String? = nil,
        heightCm: Int? = nil,
        weightKg: Int? = nil,
        injuryHistory: String? = nil,
        primaryGoal: String? = nil,
        skillLevel: String? = nil,
        expiresInDays: Int? = 30,
        accessToken: String
    ) async throws -> InviteCreatedResponse {
        try await APIClient.shared.request(
            "/api/invites",
            method: "POST",
            body: CreateInviteBody(
                expiresInDays: expiresInDays,
                clientEmail: clientEmail,
                clientName: clientName,
                clientPhone: clientPhone,
                sessionsRemaining: sessionsRemaining,
                age: age,
                gender: gender,
                heightCm: heightCm,
                weightKg: weightKg,
                injuryHistory: injuryHistory,
                primaryGoal: primaryGoal,
                skillLevel: skillLevel
            ),
            token: accessToken
        )
    }

    // MARK: - Chat

    struct CreateMessageBody: Encodable {
        let kind: String
        let body: String
        let attachmentURL: String?
    }

    struct UpdateReactionBody: Encodable {
        let reaction: String?
    }

    struct RegisterPushTokenBody: Encodable {
        let token: String
        let platform: String
    }

    struct FlushOfflineQueueBody: Encodable {
        let messages: [OfflineMessageBody]
    }

    struct OfflineMessageBody: Encodable {
        let conversationID: UUID
        let kind: String
        let body: String
        let attachmentURL: String?
    }

    static func fetchConversations(accessToken: String) async throws -> [ConversationDTO] {
        try await APIClient.shared.request("/api/conversations", token: accessToken)
    }

    static func getOrCreateMyConversation(accessToken: String) async throws -> ConversationDTO {
        try await APIClient.shared.request(
            "/api/conversations/mine",
            method: "POST",
            token: accessToken
        )
    }

    static func uploadChatAttachment(
        conversationID: UUID,
        data: Data,
        filename: String,
        mimeType: String,
        accessToken: String
    ) async throws -> AttachmentUploadResponse {
        try await APIClient.shared.upload(
            path: "/api/conversations/\(conversationID.uuidString)/attachments",
            fieldName: "file",
            fileData: data,
            filename: filename,
            mimeType: mimeType,
            token: accessToken
        )
    }

    static func getOrCreateConversation(clientID: UUID, accessToken: String) async throws -> ConversationDTO {
        try await APIClient.shared.request(
            "/api/conversations/for-client/\(clientID.uuidString)",
            method: "POST",
            token: accessToken
        )
    }

    static func fetchConversationDetail(
        id: UUID,
        includeMessages: Int = 50,
        accessToken: String
    ) async throws -> ConversationDetailResponse {
        try await APIClient.shared.request(
            "/api/conversations/\(id.uuidString)?includeMessages=\(includeMessages)",
            token: accessToken
        )
    }

    static func fetchMessages(
        conversationID: UUID,
        limit: Int = 50,
        accessToken: String
    ) async throws -> MessagesPageResponse {
        try await APIClient.shared.request(
            "/api/conversations/\(conversationID.uuidString)/messages?limit=\(limit)",
            token: accessToken
        )
    }

    static func sendMessage(
        conversationID: UUID,
        kind: MessageKind,
        attachmentURL: String? = nil,
        accessToken: String
    ) async throws -> MessageDTO {
        try await APIClient.shared.request(
            "/api/conversations/\(conversationID.uuidString)/messages",
            method: "POST",
            body: CreateMessageBody(
                kind: MessageLoader.kindString(from: kind),
                body: MessageLoader.bodyString(from: kind),
                attachmentURL: attachmentURL
            ),
            token: accessToken
        )
    }

    static func markConversationRead(conversationID: UUID, accessToken: String) async throws -> ConversationDTO {
        try await APIClient.shared.request(
            "/api/conversations/\(conversationID.uuidString)/read",
            method: "PATCH",
            token: accessToken
        )
    }

    static func setMessageReaction(
        messageID: UUID,
        reaction: Reaction?,
        accessToken: String
    ) async throws -> MessageDTO {
        try await APIClient.shared.request(
            "/api/messages/\(messageID.uuidString)/reaction",
            method: "PATCH",
            body: UpdateReactionBody(reaction: reaction?.rawValue),
            token: accessToken
        )
    }

    static func registerPushToken(_ token: String, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/devices/push-token",
            method: "POST",
            body: RegisterPushTokenBody(token: token, platform: "ios"),
            token: accessToken
        )
    }

    static func flushOfflineQueue(_ messages: [PendingChatMessage], accessToken: String) async throws -> [MessageDTO] {
        try await APIClient.shared.request(
            "/api/chat/offline-queue",
            method: "POST",
            body: FlushOfflineQueueBody(messages: messages.map {
                OfflineMessageBody(
                    conversationID: $0.conversationID,
                    kind: $0.kind,
                    body: $0.body,
                    attachmentURL: $0.attachmentURL
                )
            }),
            token: accessToken
        )
    }
}

private struct EmptyResponse: Decodable {}
