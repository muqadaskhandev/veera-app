import Foundation

enum AppleCredentialStore {
    private static let appleUserIDKey = "verra.auth.appleUserID"

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
}
