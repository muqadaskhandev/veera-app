import Foundation

/// Persists auth tokens between launches.
enum AuthStore {
    private static let accessTokenKey = "verra.auth.accessToken"
    private static let refreshTokenKey = "verra.auth.refreshToken"
    private static let onboardedTrainerKey = "verra.onboarded.trainer"
    private static let onboardedClientKey = "verra.onboarded.client"
    private static let clientDisplayNameKey = "verra.client.displayName"
    private static let clientGoalKey = "verra.client.goal"
    /// Set after a trainer finishes first-time account creation so ContentView
    /// can show the subscription upsell once (not on every later app launch).
    private static let pendingPostSignupPaywallKey = "verra.pendingPostSignupPaywall"

    static var accessToken: String? {
        get { UserDefaults.standard.string(forKey: accessTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: accessTokenKey) }
    }

    static var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshTokenKey) }
    }

    static var pendingPostSignupPaywall: Bool {
        get { UserDefaults.standard.bool(forKey: pendingPostSignupPaywallKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingPostSignupPaywallKey) }
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
        AppleCredentialStore.appleUserID = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: onboardedTrainerKey)
        defaults.removeObject(forKey: onboardedClientKey)
        defaults.removeObject(forKey: clientDisplayNameKey)
        defaults.removeObject(forKey: clientGoalKey)
        defaults.removeObject(forKey: pendingPostSignupPaywallKey)
    }
}
