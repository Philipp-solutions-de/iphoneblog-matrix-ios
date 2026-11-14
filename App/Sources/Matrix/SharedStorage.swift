import Foundation

/// Where the app and its notification extension share data: the Matrix store lives in the
/// app group's container, the session in a keychain group both targets may read.
enum SharedStorage {
    /// The app group container, or the app's own folders where no group exists
    /// (unsigned test builds).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Brand.appGroupID)
    }

    /// `<TEAMID>.<bundle id>`, the keychain group in both targets' entitlements. Nil in builds
    /// signed without a team, where the default group is used instead.
    static var keychainAccessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.hasPrefix("$") else { return nil }
        return prefix + Brand.bundleID
    }
}
