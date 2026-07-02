import Foundation

enum AppleDisplayNameSync {
    static func needsUpgrade(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Verra User" { return true }
        return trimmed.contains("@")
    }

    /// Apple only returns the user's name on first authorization — always prefer credential + keychain.
    static func resolvedForRequest(from apple: AppleSignInResult, fallbackRegisterName: String = "") -> String? {
        for candidate in [apple.displayName, AppleCredentialStore.displayName, fallbackRegisterName] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// After Apple login, patch the server profile when we have a cached name but the account still has a placeholder.
    @MainActor
    static func syncIfNeeded(currentName: String, accessToken: String) async -> String {
        guard needsUpgrade(currentName),
              let appleName = AppleCredentialStore.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appleName.isEmpty else {
            return currentName
        }

        do {
            let response = try await VerraAPI.updateProfile(
                accessToken: accessToken,
                body: UpdateProfileBody(displayName: appleName, name: appleName)
            )
            return response.profile.displayName
        } catch {
            return currentName
        }
    }
}
