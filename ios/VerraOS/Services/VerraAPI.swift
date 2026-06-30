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
    let message: String?
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
    }

    struct InviteCreatedResponse: Decodable {
        let invite: InviteCodeDTO
        let emailSent: Bool
    }

    struct InviteCodeDTO: Decodable {
        let id: UUID
        let code: String
        let trainerID: UUID
        let expiresAt: Date?
        let redeemedAt: Date?
        let isRedeemable: Bool
    }

    static func createInvite(
        clientEmail: String?,
        clientName: String?,
        expiresInDays: Int? = 30,
        accessToken: String
    ) async throws -> InviteCreatedResponse {
        try await APIClient.shared.request(
            "/api/invites",
            method: "POST",
            body: CreateInviteBody(
                expiresInDays: expiresInDays,
                clientEmail: clientEmail,
                clientName: clientName
            ),
            token: accessToken
        )
    }
}

private struct EmptyResponse: Decodable {}
