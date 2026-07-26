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

    struct UsernameAvailabilityResponse: Decodable {
        let available: Bool
        let username: String
    }

    /// Public check used by the email sign-up screen (debounced as the user types).
    static func checkUsernameAvailability(_ username: String) async throws -> UsernameAvailabilityResponse {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        return try await APIClient.shared.request(
            "/api/auth/username-availability?username=\(encoded)"
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

    static func fetchTrainerOnboarding(accessToken: String) async throws -> TrainerOnboardingResponse {
        try await APIClient.shared.request(
            "/api/onboarding/trainer",
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

    // MARK: - Google Calendar

    static func fetchGoogleCalendarStatus(accessToken: String) async throws -> GoogleCalendarStatusResponse {
        try await APIClient.shared.request("/api/calendar/google/status", token: accessToken)
    }

    static func fetchGoogleCalendarAuthorize(accessToken: String) async throws -> GoogleCalendarAuthorizeResponse {
        try await APIClient.shared.request("/api/calendar/google/authorize", token: accessToken)
    }

    struct GoogleCalendarCallbackBody: Encodable {
        let code: String
        let state: String
    }

    static func completeGoogleCalendarOAuth(code: String, state: String, accessToken: String) async throws -> GoogleCalendarStatusResponse {
        try await APIClient.shared.request(
            "/api/calendar/google/callback",
            method: "POST",
            body: GoogleCalendarCallbackBody(code: code, state: state),
            token: accessToken
        )
    }

    static func disconnectGoogleCalendar(accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/calendar/google",
            method: "DELETE",
            token: accessToken
        )
    }

    struct BusyBlockDTO: Decodable {
        let id: String
        let title: String
        let startDate: Date
        let durationMinutes: Int
    }

    static func fetchGoogleBusyBlocks(from: Date, to: Date, accessToken: String) async throws -> [BusyBlockDTO] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fromValue = formatter.string(from: from)
        let toValue = formatter.string(from: to)
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "from", value: fromValue),
            URLQueryItem(name: "to", value: toValue),
        ]
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await APIClient.shared.request(
            "/api/calendar/google/busy-blocks\(query)",
            token: accessToken
        )
    }

    struct GoogleCalendarExportBody: Encodable {
        let sessionID: UUID
        let clientName: String
        let focus: String
        let scheduledAt: Date
        let durationMinutes: Int
        let location: String?
        let notes: String?
        let reminderMinutesBefore: Int?
        let useDedicatedCalendar: Bool?
    }

    static func exportSessionToGoogleCalendar(_ body: GoogleCalendarExportBody, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/calendar/google/export",
            method: "POST",
            body: body,
            token: accessToken
        )
    }

    struct GoogleCalendarExportAllBody: Encodable {
        struct SessionPayload: Encodable {
            let sessionID: UUID
            let clientName: String
            let focus: String
            let scheduledAt: Date
            let durationMinutes: Int
            let location: String?
            let notes: String?
            let isSkipped: Bool
            let accent: String
        }

        let sessions: [SessionPayload]
        let reminderMinutesBefore: Int?
        let useDedicatedCalendar: Bool?
    }

    static func exportAllSessionsToGoogleCalendar(_ body: GoogleCalendarExportAllBody, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/calendar/google/export-all",
            method: "POST",
            body: body,
            token: accessToken
        )
    }

    static func deleteGoogleCalendarExport(sessionID: UUID, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/calendar/google/export/\(sessionID.uuidString)",
            method: "DELETE",
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
        let goalWeightKg: Int?
        let skillLevel: String?
    }

    struct InviteCreatedResponse: Decodable {
        let invite: InviteCodeDTO
        let emailSent: Bool
        let smsSent: Bool?
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

    struct InviteLinkResponse: Decodable {
        let code: String
        let url: String
    }

    static func fetchInviteLink(clientID: UUID, accessToken: String) async throws -> InviteLinkResponse {
        try await APIClient.shared.request(
            "/api/clients/\(clientID.uuidString)/invite-link",
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
        goalWeightKg: Int? = nil,
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
                goalWeightKg: goalWeightKg,
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

    static func markConversationDelivered(conversationID: UUID, accessToken: String) async throws -> [MessageDTO] {
        try await APIClient.shared.request(
            "/api/conversations/\(conversationID.uuidString)/delivered",
            method: "PATCH",
            token: accessToken
        )
    }

    struct ArchiveConversationBody: Encodable {
        let archived: Bool
    }

    static func setConversationArchived(
        conversationID: UUID,
        archived: Bool,
        accessToken: String
    ) async throws -> ConversationDTO {
        try await APIClient.shared.request(
            "/api/conversations/\(conversationID.uuidString)/archive",
            method: "PATCH",
            body: ArchiveConversationBody(archived: archived),
            token: accessToken
        )
    }

    static func deleteConversation(conversationID: UUID, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/conversations/\(conversationID.uuidString)",
            method: "DELETE",
            token: accessToken
        )
    }

    struct GifDTO: Codable, Identifiable {
        let id: String
        let title: String
        let url: String
        let previewURL: String
        let width: Int?
        let height: Int?
    }

    struct GifListResponse: Codable {
        let gifs: [GifDTO]
    }

    static func fetchTrendingGifs(limit: Int = 24, accessToken: String) async throws -> [GifDTO] {
        let response: GifListResponse = try await APIClient.shared.request(
            "/api/gifs/trending?limit=\(limit)",
            token: accessToken
        )
        return response.gifs
    }

    static func searchGifs(query: String, limit: Int = 24, accessToken: String) async throws -> [GifDTO] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let response: GifListResponse = try await APIClient.shared.request(
            "/api/gifs/search?q=\(encoded)&limit=\(limit)",
            token: accessToken
        )
        return response.gifs
    }

    struct UpdateClientBody: Encodable {
        let age: Int?
        let heightCm: Int?
        let weightKg: Int?
        let goalWeightKg: Int?
        let startWeightKg: Double?
        let note: String?
        let visibleModules: [String]?
        let isArchived: Bool?
        let sessionsRemaining: Int?
    }

    static func updateClient(
        id: UUID,
        age: Int? = nil,
        heightCm: Int? = nil,
        weightKg: Int? = nil,
        goalWeightKg: Int? = nil,
        startWeightKg: Double? = nil,
        note: String? = nil,
        visibleModules: [String]? = nil,
        isArchived: Bool? = nil,
        sessionsRemaining: Int? = nil,
        accessToken: String
    ) async throws -> ClientDTO {
        try await APIClient.shared.request(
            "/api/clients/\(id.uuidString)",
            method: "PATCH",
            body: UpdateClientBody(
                age: age,
                heightCm: heightCm,
                weightKg: weightKg,
                goalWeightKg: goalWeightKg,
                startWeightKg: startWeightKg,
                note: note,
                visibleModules: visibleModules,
                isArchived: isArchived,
                sessionsRemaining: sessionsRemaining
            ),
            token: accessToken
        )
    }

    static func deleteClient(id: UUID, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/clients/\(id.uuidString)",
            method: "DELETE",
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

    // MARK: - Sessions

    struct CreateSessionBody: Encodable {
        let id: UUID
        let clientID: UUID?
        let clientName: String
        let focus: String
        let location: String
        let accent: String
        let initials: String
        let scheduledAt: Date
        let timeZoneIdentifier: String
        let durationMinutes: Int
        let notes: String
    }

    struct UpdateSessionBody: Encodable {
        let clientID: UUID?
        let clientName: String?
        let focus: String?
        let location: String?
        let accent: String?
        let initials: String?
        let scheduledAt: Date?
        let timeZoneIdentifier: String?
        let durationMinutes: Int?
        let notes: String?
        let isCompleted: Bool?
        let isSkipped: Bool?
        let isCancelled: Bool?
    }

    static func fetchSessions(accessToken: String) async throws -> [SessionDTO] {
        try await APIClient.shared.request("/api/sessions", token: accessToken)
    }

    static func createSession(_ body: CreateSessionBody, accessToken: String) async throws -> SessionDTO {
        try await APIClient.shared.request("/api/sessions", method: "POST", body: body, token: accessToken)
    }

    static func updateSession(id: UUID, body: UpdateSessionBody, accessToken: String) async throws -> SessionDTO {
        try await APIClient.shared.request("/api/sessions/\(id.uuidString)", method: "PATCH", body: body, token: accessToken)
    }

    static func deleteSession(id: UUID, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/sessions/\(id.uuidString)",
            method: "DELETE",
            token: accessToken
        )
    }

    // MARK: - Financials

    struct FinancialEventDTO: Codable {
        let id: UUID
        let trainerID: UUID
        let clientID: UUID?
        let sessionID: UUID?
        let clientName: String?
        let kind: String
        let title: String
        let detail: String
        let amount: Double?
        let sessionDelta: Int
        let occurredAt: Date
    }

    struct FinancialBucketDTO: Codable {
        let label: String
        let revenue: Double
        let sessions: Int
    }

    struct FinancialSummaryDTO: Codable {
        let revenue: Double
        let sessionsUsed: Int
        let events: [FinancialEventDTO]
        let buckets: [FinancialBucketDTO]?
    }

    static func fetchFinancialSummary(filter: String, accessToken: String) async throws -> FinancialSummaryDTO {
        try await APIClient.shared.request("/api/financials?filter=\(filter)", token: accessToken)
    }

    static func fetchClientLedger(clientID: UUID, accessToken: String) async throws -> [FinancialEventDTO] {
        try await APIClient.shared.request("/api/financials/clients/\(clientID.uuidString)", token: accessToken)
    }

    static func createFinancialEvent(_ body: CreateFinancialEventBody, accessToken: String) async throws -> FinancialEventDTO {
        try await APIClient.shared.request("/api/financials", method: "POST", body: body, token: accessToken)
    }

    struct CreateFinancialEventBody: Encodable {
        let clientID: UUID
        let kind: String
        let title: String
        let detail: String?
        let amount: Double?
        let sessionDelta: Int?
    }

    // MARK: - Workouts & profile modules

    struct WorkoutExerciseDTO: Codable {
        let id: UUID?
        let exerciseID: UUID?
        let name: String
        let category: String?
        let sets: Int?
        let reps: Int?
        let kind: String
        let weightKg: Double?
    }

    struct WorkoutDayDTO: Codable {
        let id: UUID?
        let label: String
        let focus: String?
        let exercises: [WorkoutExerciseDTO]
        let notes: String?
    }

    struct WorkoutWeekResponse: Codable {
        let weekIndex: Int
        let weekCount: Int
        let days: [WorkoutDayDTO]
    }

    struct SaveWorkoutWeekBody: Encodable {
        let days: [WorkoutDayDTO]
        let weekCount: Int?
    }

    static func fetchWorkoutWeek(clientID: UUID, week: Int, accessToken: String) async throws -> WorkoutWeekResponse {
        try await APIClient.shared.request("/api/clients/\(clientID.uuidString)/workouts?week=\(week)", token: accessToken)
    }

    static func saveWorkoutWeek(clientID: UUID, week: Int, body: SaveWorkoutWeekBody, accessToken: String) async throws -> WorkoutWeekResponse {
        try await APIClient.shared.request(
            "/api/clients/\(clientID.uuidString)/workouts/\(week)",
            method: "PUT",
            body: body,
            token: accessToken
        )
    }

    struct WeightLogDTO: Codable {
        let id: UUID
        let kg: Double
        let recordedAt: Date
    }

    static func fetchWeightLogs(clientID: UUID, accessToken: String) async throws -> [WeightLogDTO] {
        try await APIClient.shared.request("/api/clients/\(clientID.uuidString)/weight", token: accessToken)
    }

    static func logWeight(
        clientID: UUID,
        kg: Double,
        recordedAt: Date? = nil,
        accessToken: String
    ) async throws -> WeightLogDTO {
        struct Body: Encodable {
            let kg: Double
            let recordedAt: Date?
        }
        return try await APIClient.shared.request(
            "/api/clients/\(clientID.uuidString)/weight",
            method: "POST",
            body: Body(kg: kg, recordedAt: recordedAt),
            token: accessToken
        )
    }

    struct NutritionProfileDTO: Codable {
        let proteinG: Int
        let carbsG: Int
        let fatsG: Int
        let calories: Int
        let notes: [NutritionNoteDTO]
        let supplements: [SupplementDTO]
    }

    struct NutritionNoteDTO: Codable {
        let id: UUID
        let text: String
    }

    struct SupplementDTO: Codable {
        let id: UUID
        let name: String
        let dosage: String
    }

    static func fetchNutrition(clientID: UUID, accessToken: String) async throws -> NutritionProfileDTO {
        try await APIClient.shared.request("/api/clients/\(clientID.uuidString)/nutrition", token: accessToken)
    }

    struct NutritionNoteInput: Encodable {
        let id: UUID?
        let text: String
    }

    struct SupplementInput: Encodable {
        let id: UUID?
        let name: String
        let dosage: String
    }

    struct UpdateNutritionBody: Encodable {
        let proteinG: Int?
        let carbsG: Int?
        let fatsG: Int?
        let notes: [NutritionNoteInput]?
        let supplements: [SupplementInput]?
    }

    static func updateNutrition(clientID: UUID, body: UpdateNutritionBody, accessToken: String) async throws -> NutritionProfileDTO {
        try await APIClient.shared.request(
            "/api/clients/\(clientID.uuidString)/nutrition",
            method: "PATCH",
            body: body,
            token: accessToken
        )
    }

    struct ProgressPhotoDTO: Codable {
        let id: UUID
        let imageURL: String
        let capturedAt: Date
    }

    static func fetchProgressPhotos(clientID: UUID, accessToken: String) async throws -> [ProgressPhotoDTO] {
        try await APIClient.shared.request("/api/clients/\(clientID.uuidString)/photos", token: accessToken)
    }

    static func uploadProgressPhoto(clientID: UUID, imageData: Data, accessToken: String) async throws -> ProgressPhotoDTO {
        try await APIClient.shared.upload(
            path: "/api/clients/\(clientID.uuidString)/photos",
            fieldName: "photo",
            fileData: imageData,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            token: accessToken
        )
    }

    static func deleteProgressPhoto(clientID: UUID, photoID: UUID, accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/clients/\(clientID.uuidString)/photos/\(photoID.uuidString)",
            method: "DELETE",
            token: accessToken
        )
    }

    struct ExerciseDTO: Codable {
        let id: UUID
        let name: String
        let category: String
        let description: String?
        let imageURL: String?
        let videoURL: String?
    }

    static func fetchExerciseCategories(accessToken: String) async throws -> [String] {
        try await APIClient.shared.request("/api/exercises/categories", token: accessToken)
    }

    static func fetchExercises(
        query: String? = nil,
        category: String? = nil,
        limit: Int = 30,
        accessToken: String
    ) async throws -> [ExerciseDTO] {
        var parts: [String] = []
        if let query, !query.isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            parts.append("q=\(encoded)")
        }
        if let category, !category.isEmpty {
            parts.append("category=\(category)")
        }
        parts.append("limit=\(limit)")
        let queryString = parts.joined(separator: "&")
        return try await APIClient.shared.request("/api/exercises?\(queryString)", token: accessToken)
    }

    static func fetchExercise(id: UUID, accessToken: String) async throws -> ExerciseDTO {
        try await APIClient.shared.request("/api/exercises/\(id.uuidString)", token: accessToken)
    }

    static func createExercise(
        name: String,
        category: String,
        description: String?,
        accessToken: String
    ) async throws -> ExerciseDTO {
        struct Body: Encodable {
            let name: String
            let category: String
            let description: String?
        }
        return try await APIClient.shared.request(
            "/api/exercises",
            method: "POST",
            body: Body(name: name, category: category, description: description),
            token: accessToken
        )
    }

    static func uploadExerciseImage(exerciseID: UUID, imageData: Data, accessToken: String) async throws -> ExerciseDTO {
        try await APIClient.shared.upload(
            path: "/api/exercises/\(exerciseID.uuidString)/image",
            fieldName: "image",
            fileData: imageData,
            filename: "exercise.jpg",
            mimeType: "image/jpeg",
            token: accessToken
        )
    }

    static func uploadExerciseVideo(exerciseID: UUID, videoData: Data, accessToken: String) async throws -> ExerciseDTO {
        try await APIClient.shared.upload(
            path: "/api/exercises/\(exerciseID.uuidString)/video",
            fieldName: "video",
            fileData: videoData,
            filename: "exercise.mp4",
            mimeType: "video/mp4",
            token: accessToken
        )
    }

    static func searchExercises(query: String, accessToken: String) async throws -> [ExerciseDTO] {
        try await fetchExercises(query: query, accessToken: accessToken)
    }

    // MARK: - Notifications

    struct UserNotificationDTO: Codable {
        let id: UUID
        let category: String
        let title: String
        let body: String
        let isRead: Bool
        let createdAt: Date?
    }

    struct NotificationPreferencesDTO: Codable {
        let notificationsEnabled: Bool
        let notifyMoney: Bool
        let notifySchedule: Bool
        let notifyMessages: Bool
        let notifyActivity: Bool
        let activityMode: String
        let quietHoursEnabled: Bool
        let quietStartMinutes: Int
        let quietEndMinutes: Int
        let smsEnabled: Bool
        let reminderMinutesBefore: Int
    }

    struct UpdateNotificationPreferencesBody: Encodable {
        var notificationsEnabled: Bool? = nil
        var notifyMoney: Bool? = nil
        var notifySchedule: Bool? = nil
        var notifyMessages: Bool? = nil
        var notifyActivity: Bool? = nil
        var activityMode: String? = nil
        var quietHoursEnabled: Bool? = nil
        var quietStartMinutes: Int? = nil
        var quietEndMinutes: Int? = nil
        var smsEnabled: Bool? = nil
        var reminderMinutesBefore: Int? = nil
    }

    static func fetchNotifications(accessToken: String) async throws -> [UserNotificationDTO] {
        try await APIClient.shared.request("/api/notifications", token: accessToken)
    }

    static func markNotificationRead(id: UUID, accessToken: String) async throws {
        try await APIClient.shared.requestVoid(
            "/api/notifications/\(id.uuidString)/read",
            method: "PATCH",
            token: accessToken
        )
    }

    static func markAllNotificationsRead(accessToken: String) async throws {
        try await APIClient.shared.requestVoid(
            "/api/notifications/read-all",
            method: "PATCH",
            token: accessToken
        )
    }

    static func fetchNotificationPreferences(accessToken: String) async throws -> NotificationPreferencesDTO {
        try await APIClient.shared.request("/api/notifications/preferences", token: accessToken)
    }

    static func updateNotificationPreferences(_ body: UpdateNotificationPreferencesBody, accessToken: String) async throws -> NotificationPreferencesDTO {
        try await APIClient.shared.request(
            "/api/notifications/preferences",
            method: "PATCH",
            body: body,
            token: accessToken
        )
    }

    // MARK: - Account

    static func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws {
        struct Body: Encodable {
            let currentPassword: String
            let newPassword: String
        }
        let _: MessageResponse = try await APIClient.shared.request(
            "/api/account/password",
            method: "PATCH",
            body: Body(currentPassword: currentPassword, newPassword: newPassword),
            token: accessToken
        )
    }

    static func deleteAccount(accessToken: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.request(
            "/api/account",
            method: "DELETE",
            token: accessToken
        )
    }

    static func submitSupportTicket(topic: String, message: String, attachmentData: Data?, accessToken: String) async throws {
        let _: SupportTicketResponse = try await APIClient.shared.uploadMultipart(
            path: "/api/account/support",
            fields: [
                "topic": topic,
                "message": message,
            ],
            fileField: attachmentData == nil ? nil : "attachment",
            fileData: attachmentData,
            filename: "screenshot.jpg",
            mimeType: "image/jpeg",
            token: accessToken
        )
    }

    struct MessageResponse: Codable {
        let message: String
    }

    struct SupportTicketResponse: Codable {
        let id: UUID
        let topic: String
        let status: String
    }

    // MARK: - Subscriptions

    struct SubscriptionDTO: Codable {
        let productID: String
        let status: String
        let startedAt: Date?
        let expiresAt: Date?
        let isActive: Bool
    }

    static func fetchCurrentSubscription(accessToken: String) async throws -> SubscriptionDTO {
        try await APIClient.shared.request("/api/subscriptions/me", token: accessToken)
    }

    /// Returns the subscription when one exists, or `nil` when the server has none on file.
    /// Other errors (network, auth) are thrown so callers don't treat a failed check as "no sub".
    static func fetchCurrentSubscriptionIfPresent(accessToken: String) async throws -> SubscriptionDTO? {
        do {
            return try await fetchCurrentSubscription(accessToken: accessToken)
        } catch let APIError.server(message)
            where message.localizedCaseInsensitiveContains("no subscription") {
            return nil
        } catch {
            throw error
        }
    }

    static func validateReceipt(receiptData: String, productID: String, accessToken: String) async throws -> SubscriptionDTO {
        struct Body: Encodable {
            let receiptData: String
            let productID: String
        }
        return try await APIClient.shared.request(
            "/api/subscriptions/validate",
            method: "POST",
            body: Body(receiptData: receiptData, productID: productID),
            token: accessToken
        )
    }

    // MARK: - Payments (Stripe + Apple Pay)

    struct PaymentConfigDTO: Decodable {
        let configured: Bool
        let publishableKey: String?
        let merchantID: String?
        let merchantCountryCode: String
        let monthlyAmount: Int
        let annualAmount: Int
        let currency: String
    }

    struct CreatePaymentIntentBody: Encodable {
        let productType: String
        let plan: String?
        let clientID: UUID?
        let amount: Int?
        let sessionCount: Int?
        let currency: String?
    }

    struct PaymentIntentDTO: Decodable {
        let clientSecret: String
        let paymentIntentID: String
        let amount: Int
        let currency: String
    }

    struct PaymentStatusDTO: Decodable {
        let paymentIntentID: String
        let status: String
        let fulfilled: Bool
    }

    static func fetchPaymentConfig(accessToken: String) async throws -> PaymentConfigDTO {
        try await APIClient.shared.request("/api/payments/config", token: accessToken)
    }

    static func createPaymentIntent(_ body: CreatePaymentIntentBody, accessToken: String) async throws -> PaymentIntentDTO {
        try await APIClient.shared.request(
            "/api/payments/intent",
            method: "POST",
            body: body,
            token: accessToken
        )
    }

    static func fetchPaymentStatus(paymentIntentID: String, accessToken: String) async throws -> PaymentStatusDTO {
        try await APIClient.shared.request(
            "/api/payments/intent/\(paymentIntentID)",
            token: accessToken
        )
    }
}

private struct EmptyResponse: Decodable {}
