import Foundation

/// Shared post-sign-up work: persist tokens and save trainer onboarding answers.
enum OnboardingAuthService {
    @MainActor
    static func complete(
        role: OnboardingRole,
        auth: AuthTokenResponse,
        trainerAnswers: [String: String],
        onComplete: (String) -> Void
    ) async throws {
        AuthStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken)

        if role == .trainer, !trainerAnswers.isEmpty {
            _ = try await VerraAPI.saveTrainerOnboarding(
                answers: trainerAnswers,
                accessToken: auth.accessToken
            )
        }

        onComplete(auth.user.displayName)
    }
}
