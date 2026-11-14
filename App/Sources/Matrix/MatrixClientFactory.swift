import Foundation
import MatrixRustSDK

/// Builds Matrix clients the same way everywhere: preset server, our store paths,
/// native sliding sync, threads on, and no end-to-end encryption setup.
enum MatrixClientFactory {
    /// The client API the app talks to. Tests and the debug settings may point elsewhere;
    /// members never see a server choice.
    static func homeserverURL(override: String? = nil) -> String {
        override ?? ProcessInfo.processInfo.environment["IPHONEBLOG_HOMESERVER"] ?? Brand.homeserverURL
    }

    /// `process` names the holder of the store's cross-process lock: the app and the
    /// notification extension open the same store and must not refresh tokens at once.
    static func makeClient(homeserverURL: String,
                           storeID: String,
                           sessionDelegate: ClientSessionDelegate? = nil,
                           process: String = "app") async throws -> Client {
        let paths = try StorePaths(storeID: storeID)
        var builder = ClientBuilder()
            .homeserverUrl(url: homeserverURL)
            .sqliteStore(config: SqliteStoreBuilder(dataPath: paths.data.path, cachePath: paths.cache.path))
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            // No encryption in this community: never create cross-signing keys or backups,
            // so a new device has nothing to confirm.
            .autoEnableCrossSigning(autoEnableCrossSigning: false)
            .autoEnableBackups(autoEnableBackups: false)
            .threadsEnabled(enabled: true, threadSubscriptions: false)
            .crossProcessLockConfig(crossProcessLockConfig: .multiProcess(holderName: process))
            .userAgent(userAgent: "\(Brand.appName)/\(Bundle.main.shortVersion) iOS")
        if let sessionDelegate {
            builder = builder.setSessionDelegate(sessionDelegate: sessionDelegate)
        }
        return try await builder.build()
    }

    static func deleteStore(storeID: String) {
        guard let paths = try? StorePaths(storeID: storeID) else { return }
        try? FileManager.default.removeItem(at: paths.data)
        try? FileManager.default.removeItem(at: paths.cache)
    }
}

struct StorePaths {
    let data: URL
    let cache: URL

    init(storeID: String) throws {
        let fm = FileManager.default
        if let shared = SharedStorage.containerURL {
            // Shared with the notification extension, which reads the same store.
            data = shared.appending(path: "Library/Application Support/matrix/\(storeID)", directoryHint: .isDirectory)
            cache = shared.appending(path: "Library/Caches/matrix/\(storeID)", directoryHint: .isDirectory)
        } else {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            data = support.appending(path: "matrix/\(storeID)", directoryHint: .isDirectory)
            cache = caches.appending(path: "matrix/\(storeID)", directoryHint: .isDirectory)
        }
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
