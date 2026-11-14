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

    static func makeClient(homeserverURL: String,
                           storeID: String,
                           sessionDelegate: ClientSessionDelegate? = nil) async throws -> Client {
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
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        data = support.appending(path: "matrix/\(storeID)", directoryHint: .isDirectory)
        cache = caches.appending(path: "matrix/\(storeID)", directoryHint: .isDirectory)
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
