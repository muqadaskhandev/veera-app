import AuthenticationServices

enum AppleCredentialChecker {
    /// Returns `false` when a stored Apple user ID was revoked or removed at the OS level.
    @MainActor
    static func validateStoredCredential() async -> Bool {
        guard let userID = AppleCredentialStore.appleUserID else { return true }

        return await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                switch state {
                case .authorized:
                    continuation.resume(returning: true)
                case .revoked, .notFound, .transferred:
                    AuthStore.signOut()
                    continuation.resume(returning: false)
                @unknown default:
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
