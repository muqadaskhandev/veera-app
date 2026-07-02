import Foundation

enum AppleCredentialStore {
    private static let appleUserIDKey = "verra.auth.appleUserID"
    private static let appleDisplayNameKey = "verra.auth.appleDisplayName"

    static var appleUserID: String? {
        get { KeychainHelper.read(key: appleUserIDKey) }
        set {
            if let newValue {
                KeychainHelper.save(key: appleUserIDKey, value: newValue)
            } else {
                KeychainHelper.delete(key: appleUserIDKey)
            }
        }
    }

    /// Apple only returns the user's name on the first authorization — cache it for later sign-ins.
    static var displayName: String? {
        get { KeychainHelper.read(key: appleDisplayNameKey) }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainHelper.save(key: appleDisplayNameKey, value: newValue)
            } else {
                KeychainHelper.delete(key: appleDisplayNameKey)
            }
        }
    }
}
