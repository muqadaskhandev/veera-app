import Foundation

enum SessionRestoreService {
    /// Validates Apple credential state (if applicable), then restores the backend session.
    @MainActor
    static func restoreSession() async -> AuthUserDTO? {
        guard AuthStore.accessToken != nil else { return nil }

        guard await AppleCredentialChecker.validateStoredCredential() else {
            return nil
        }

        if let accessToken = AuthStore.accessToken {
            do {
                return try await VerraAPI.me(accessToken: accessToken)
            } catch {
                // Access token may have expired; try refresh below.
            }
        }

        guard let refreshToken = AuthStore.refreshToken else {
            AuthStore.signOut()
            return nil
        }

        do {
            let auth = try await VerraAPI.refresh(refreshToken: refreshToken)
            AuthStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
            return auth.user
        } catch {
            AuthStore.signOut()
            return nil
        }
    }
}
