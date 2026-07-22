import Foundation

/// Shared post-sign-up work: persist tokens, save trainer onboarding answers,
/// and apply the profile draft collected during onboarding.
enum OnboardingAuthService {
    /// Profile fields gathered on the profile-setup step (and coaching focus).
    struct ProfileDraft {
        var displayName: String
        var jobTitle: String
        var bio: String
        var specialties: [String]
        var primaryCoachingFocus: [String]
    }

    @MainActor
    static func complete(
        role: OnboardingRole,
        auth: AuthTokenResponse,
        trainerAnswers: [String: String],
        profileDraft: ProfileDraft? = nil,
        onComplete: (String) -> Void
    ) async throws {
        AuthStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken)

        if role == .trainer, !trainerAnswers.isEmpty {
            _ = try await VerraAPI.saveTrainerOnboarding(
                answers: trainerAnswers,
                accessToken: auth.accessToken
            )
        }

        if let draft = profileDraft {
            try await applyProfileDraft(draft, accessToken: auth.accessToken)
        }

        let preferredName: String = {
            if let draft = profileDraft {
                let trimmed = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return auth.user.displayName
        }()

        let displayName = await AppleDisplayNameSync.syncIfNeeded(
            currentName: preferredName,
            accessToken: auth.accessToken
        )
        onComplete(displayName)
    }

    @MainActor
    private static func applyProfileDraft(_ draft: ProfileDraft, accessToken: String) async throws {
        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = draft.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let bio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty || !title.isEmpty || !bio.isEmpty || !draft.specialties.isEmpty else {
            return
        }

        _ = try await VerraAPI.updateProfile(
            accessToken: accessToken,
            body: UpdateProfileBody(
                displayName: name.isEmpty ? nil : name,
                name: name.isEmpty ? nil : name,
                title: title.isEmpty ? nil : title,
                bio: bio.isEmpty ? nil : bio,
                specialties: draft.specialties.isEmpty ? nil : draft.specialties
            )
        )
    }
}
