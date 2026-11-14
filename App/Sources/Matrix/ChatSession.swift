import Foundation
import MatrixRustSDK
import OSLog
import UIKit

/// Where the app is: the tab, the open room, the open thread. One per signed-in account.
@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case chats, threads, mentions, me }

    struct ThreadRoute: Hashable {
        let roomID: String
        let rootEventID: String
    }

    @Published var tab: Tab = .chats
    @Published var selectedRoomID: String?
    @Published var threadPath: [ThreadRoute] = []
    @Published var presentedURL: URL?
    @Published var notice: String?

    func openRoom(_ roomID: String) {
        tab = .chats
        threadPath = []
        selectedRoomID = roomID
    }

    /// A thread to open once its channel's screen exists (set from another tab or a push).
    @Published var pendingThread: ThreadRoute?

    func openThread(roomID: String, rootEventID: String) {
        let route = ThreadRoute(roomID: roomID, rootEventID: rootEventID)
        if tab == .chats, selectedRoomID == roomID {
            threadPath = [route]
        } else {
            // Switching tab or channel rebuilds the channel's navigation stack, which would drop a
            // path set now. ChatsView opens the pending thread once the stack is on screen.
            pendingThread = route
            openRoom(roomID)
        }
    }
}

/// A signed-in account: the client, its sync loop, the room list and push.
/// It is the `ChatHost` the conversation views in Vendor/ talk to.
@MainActor
final class ChatSession: ObservableObject, ChatHost {
    let client: Client
    let userID: String
    let rooms = RoomListModel()
    let router = Router()

    @Published private(set) var syncState: SyncServiceState = .idle
    @Published private(set) var displayName: String?

    private var syncService: SyncService?
    private var stateHandle: TaskHandle?
    private var pushToken: Data?
    private let log = Logger(subsystem: Brand.bundleID, category: "session")

    init(client: Client) throws {
        self.client = client
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
        try await ChatScreens.provider.start(host: self)
        displayName = try? await client.displayName()
        log.info("sync started")
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
