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
                let user = try await VerraAPI.me(accessToken: accessToken)
                let displayName = await AppleDisplayNameSync.syncIfNeeded(
                    currentName: user.displayName,
                    accessToken: accessToken
                )
                if displayName == user.displayName {
                    return user
                }
                return AuthUserDTO(
                    id: user.id,
                    email: user.email,
                    role: user.role,
                    displayName: displayName
                )
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
            let displayName = await AppleDisplayNameSync.syncIfNeeded(
                currentName: auth.user.displayName,
                accessToken: auth.accessToken
            )
            if displayName == auth.user.displayName {
                return auth.user
            }
            return AuthUserDTO(
                id: auth.user.id,
                email: auth.user.email,
                role: auth.user.role,
                displayName: displayName
            )
        } catch {
            AuthStore.signOut()
            return nil
        }
    }
}
