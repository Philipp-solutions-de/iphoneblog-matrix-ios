import Combine
import Foundation
import MatrixRustSDK
import OSLog
import UIKit

/// A signed-in account: the client, its sync loop, the room list and push.
/// It is the `ChatHost` the conversation views in Vendor/ talk to.
@MainActor
final class ChatSession: ObservableObject, ChatHost {
    let client: Client
    let userID: String
    let rooms = RoomListModel()
    let router: Router
    /// The Blog room and whether this person may use #one-Chat; set once sync runs.
    @Published private(set) var blogRoomID: String?
    @Published private(set) var isOneMember = false

    @Published private(set) var syncState: SyncServiceState = .idle
    @Published private(set) var displayName: String?

    /// The Blog tab's articles through the SDK, once the Blog room is known.
    @Published private(set) var blogFeed: MatrixBlogFeed?
    private var oneRoomID: String?
    private var membershipWatch: AnyCancellable?

    private var syncService: SyncService?
    private var stateHandle: TaskHandle?
    private var pushToken: Data?
    private let log = Logger(subsystem: Brand.bundleID, category: "session")

    init(client: Client, router: Router) throws {
        self.client = client
        self.router = router
        userID = try client.userId()
    }

    var roomListService: RoomListService {
        // Only read after start(); the views exist only once sync runs.
        syncService!.roomListService() // swiftlint:disable:this force_unwrapping
    }

    /// Starts sliding sync and the room list. Safe to call again after `stop()`.
    func start() async throws {
        if syncService == nil {
            let service = try await client.syncService().finish()
            syncService = service
            stateHandle = service.state(listener: SyncStateObserver { [weak self] state in
                Task { @MainActor in self?.syncState = state }
            })
            try await rooms.attach(to: service.roomListService())
        }
        await syncService?.start()
        await resolveRooms()
        try await ChatScreens.provider.start(host: self)
        displayName = try? await client.displayName()
        log.info("sync started")
    }

    /// Finds the Blog room (joining it if needed, it is open to everyone) and the #one room,
    /// whose presence among the joined rooms makes someone a member. A lapsed membership drops
    /// the room and locks #one-Chat on the next sync.
    private func resolveRooms() async {
        if let blog = try? await client.resolveRoomAlias(roomAlias: Self.alias("IPHONEBLOG_BLOG_ALIAS", Brand.blogRoomAlias)) {
            blogRoomID = blog.roomId
            router.blogRoomID = blog.roomId
            rooms.hidden = [blog.roomId]
            var room = try? client.getRoom(roomId: blog.roomId)
            if room == nil { room = try? await client.joinRoomById(roomId: blog.roomId) }
            if let room, blogFeed == nil { blogFeed = MatrixBlogFeed(room: room) }
        } else {
            log.error("blog room alias does not resolve")
        }
        oneRoomID = try? await client.resolveRoomAlias(roomAlias: Self.alias("IPHONEBLOG_ONE_ALIAS", Brand.oneRoomAlias))?.roomId
        membershipWatch = rooms.$rooms.sink { [weak self] list in
            guard let self, let one = self.oneRoomID else { return }
            let member = list.contains { $0.id == one }
            if member != self.isOneMember { self.isOneMember = member }
        }
    }

    /// Room aliases from brand.env; debug runs against a test server may name others.
    private static func alias(_ key: String, _ fallback: String) -> String {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { return value }
        #endif
        return fallback
    }

    func stop() async {
        await syncService?.stop()
    }

    // MARK: - ChatHost

    func openThread(roomID: String, rootEventID: String) {
        router.openThread(roomID: roomID, rootEventID: rootEventID)
    }

    func openUser(userID: String) {
        // Profiles come with the conversation views; until then a mention opens nothing.
        log.info("open user requested")
    }

    func openRoom(roomID: String) {
        router.openRoom(roomID)
    }

    func openURL(_ url: URL) {
        router.presentedURL = url
    }

    func showMessage(_ text: String) {
        router.notice = text
    }

    // MARK: - Push

    /// Registers this device with our Sygnal. Called with the APNs token after sign-in and
    /// whenever iOS hands out a new token.
    func registerPusher(token: Data) async {
        pushToken = token
        let identifiers = PusherIdentifiers(pushkey: token.base64EncodedString(), appId: Brand.pusherAppID)
        // Sygnal sends only the event and room id; the notification extension fetches the
        // message and writes the text. mutable-content wakes the extension.
        let payload = #"{"aps":{"mutable-content":1,"alert":{"loc-key":"Notification","loc-args":[]}}}"#
        do {
            try await client.setPusher(identifiers: identifiers,
                                       kind: .http(data: HttpPusherData(url: Brand.pushGatewayURL,
                                                                        format: .eventIdOnly,
                                                                        defaultPayload: payload)),
                                       appDisplayName: Brand.appName,
                                       deviceDisplayName: UIDevice.current.name,
                                       profileTag: nil,
                                       lang: Locale.preferredLanguages.first ?? "de",
                                       append: false)
            log.info("pusher registered")
        } catch {
            log.error("pusher registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes this device's pusher, before signing out.
    func unregisterPusher() async {
        guard let pushToken else { return }
        let identifiers = PusherIdentifiers(pushkey: pushToken.base64EncodedString(), appId: Brand.pusherAppID)
        try? await client.deletePusher(identifiers: identifiers)
    }

    /// The account page on the sign-in service (name, password, devices).
    func accountURL() async -> URL? {
        guard let string = try? await client.accountUrl(action: nil) else { return nil }
        return URL(string: string)
    }
}

private final class SyncStateObserver: SyncServiceStateObserver, @unchecked Sendable {
    let onChange: (SyncServiceState) -> Void
    init(_ onChange: @escaping (SyncServiceState) -> Void) { self.onChange = onChange }
    func onUpdate(state: SyncServiceState) { onChange(state) }
}
