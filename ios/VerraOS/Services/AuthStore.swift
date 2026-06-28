import Foundation

/// Persists auth tokens between launches.
enum AuthStore {
    private static let accessTokenKey = "verra.auth.accessToken"
    private static let refreshTokenKey = "verra.auth.refreshToken"
    private static let onboardedTrainerKey = "verra.onboarded.trainer"
    private static let onboardedClientKey = "verra.onboarded.client"
    private static let clientDisplayNameKey = "verra.client.displayName"
    private static let clientGoalKey = "verra.client.goal"

    static var accessToken: String? {
        get { UserDefaults.standard.string(forKey: accessTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: accessTokenKey) }
    }

    static var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshTokenKey) }
    }

    static func save(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    static func clear() {
        accessToken = nil
        refreshToken = nil
    }

    /// Clears auth tokens and local onboarding flags so the welcome flow can run again.
    static func signOut() {
        clear()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: onboardedTrainerKey)
        defaults.removeObject(forKey: onboardedClientKey)
        defaults.removeObject(forKey: clientDisplayNameKey)
        defaults.removeObject(forKey: clientGoalKey)
    }
}
