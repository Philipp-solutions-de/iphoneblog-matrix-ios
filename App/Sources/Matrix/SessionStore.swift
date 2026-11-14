import Foundation
import MatrixRustSDK
import Security

/// The signed-in session, kept in the keychain. One account per install.
struct StoredSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var userID: String
    var deviceID: String
    var homeserverURL: String
    var oauthData: String?
    /// "native" or "none"; the SDK's enum is not Codable.
    var slidingSyncVersion: String
    /// The folder of this session's Matrix store.
    var storeID: String

    init(_ session: Session, storeID: String) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userID = session.userId
        deviceID = session.deviceId
        homeserverURL = session.homeserverUrl
        oauthData = session.oauthData
        slidingSyncVersion = session.slidingSyncVersion == .native ? "native" : "none"
        self.storeID = storeID
    }

    var sdkSession: Session {
        Session(accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userID,
                deviceId: deviceID,
                homeserverUrl: homeserverURL,
                oauthData: oauthData,
                slidingSyncVersion: slidingSyncVersion == "native" ? .native : .none)
    }
}

/// Reads and writes the session in the keychain. The service name is the bundle id,
/// so a test host and the app never share an entry.
struct SessionStore {
    var service = Bundle.main.bundleIdentifier ?? Brand.bundleID
    var account = "session"

    func load() -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SessionStoreError.keychain(status) }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

enum SessionStoreError: Error {
    case keychain(OSStatus)
    case noSession
}

/// Hands refreshed OAuth tokens from the SDK to the keychain.
final class KeychainSessionDelegate: ClientSessionDelegate, @unchecked Sendable {
    private let store: SessionStore
    private let storeID: String

    init(store: SessionStore, storeID: String) {
        self.store = store
        self.storeID = storeID
    }

    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        guard let stored = store.load(), stored.userID == userId else { throw SessionStoreError.noSession }
        return stored.sdkSession
    }

    func saveSessionInKeychain(session: Session) {
        try? store.save(StoredSession(session, storeID: storeID))
    }
}
