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
    let mentions = MentionsModel()
    let notificationPrefs = NotificationPrefs()
    let router: Router
    /// The Blog room and whether this person may use #one-Chat; set once sync runs.
    @Published private(set) var blogRoomID: String?
    @Published private(set) var isOneMember = false

    @Published private(set) var syncState: SyncServiceState = .idle
    @Published private(set) var displayName: String?
    /// The profile picture, small, for Ich; nil without one.
    @Published private(set) var avatar: UIImage?

    /// #one-Chat's first room ("Allgemein"); the push-rule mode is read from it.
    @Published private(set) var oneChannelID: String?
    /// The #one rooms in their order, from the server's list (GET /_iphoneblog/v1/rooms,
    /// 2026-11-14_interfaces.md "The #one rooms"), else from the space #one's children.
    /// A non-member gets them locked: listed, not opened.
    @Published private(set) var oneRooms: [OneRoom] = []
    struct OneRoom: Identifiable, Equatable {
        let id: String
        var name: String
        var topic: String?
        var locked: Bool
    }
    /// The space's children in the order the space lists them (the fallback's order).
    private var spaceOrder: [String] = []
    private var oneRoomID: String?
    private var membershipWatch: AnyCancellable?
    private var membershipTimer: Task<Void, Never>?
    private var badgeWatch: AnyCancellable?
    /// Called once AuthGuard is sure the session is over (AppModel signs out).
    var onAuthLost: (() -> Void)?
    /// Checks every token error before anyone signs out (AuthGuard).
    private(set) lazy var authGuard = AuthGuard(probes: authProbes,
                                                report: { MetricsReporter.shared.breadcrumb($0) }) { [weak self] reason in
        self?.log.error("session over: \(reason, privacy: .public)")
        self?.onAuthLost?()
    }
    private var membershipRetry: Task<Void, Never>?

    private var syncService: SyncService?
    private var stateHandle: TaskHandle?
    private var pushToken: Data?
    private let log = Logger(subsystem: Brand.bundleID, category: "session")

    init(client: Client, router: Router) throws {
        self.client = client
        self.router = router
        userID = try client.userId()
        AvatarStore.shared.client = client
        refreshWatch = NotificationCenter.default.addObserver(forName: KeychainSessionDelegate.didSave, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.authGuard.noteRefresh() }
        }
    }

    private var refreshWatch: NSObjectProtocol?

    var roomListService: RoomListService {
        // Only read after start(); the views exist only once sync runs.
        syncService!.roomListService() // swiftlint:disable:this force_unwrapping
    }

    /// Starts sliding sync and the room list. Safe to call again after `stop()`.
    func start() async throws {
        if syncService == nil {
            // The send queue reports how far an upload is; the message row shows it as a bar.
            client.enableSendQueueUploadProgress(enable: true)
            // Offline mode: on a network error or a server that is down, the SDK waits and
            // reconnects by itself, with backoff, instead of stopping for good (testers: "die App
            // aktualisiert sich nicht, ich muss sie abschiessen").
            let service = try await client.syncService().withOfflineMode().finish()
            syncService = service
            stateHandle = service.state(listener: SyncStateObserver { [weak self] state in
                Task { @MainActor in self?.syncStateChanged(state) }
            })
            try await rooms.attach(to: service.roomListService())
        }
        await syncService?.start()
        await resolveRooms()
        try await ChatScreens.provider.start(host: self)
        mentions.attach(to: self)
        notificationPrefs.attach(to: self)
        displayName = try? await client.displayName()
        await loadAvatar()
        log.info("sync started")
    }

    // MARK: Keeping sync alive

    private var restartTask: Task<Void, Never>?
    private var restartAttempt = 0
    private var inForeground = true

    /// Sync ended in an error: if the token was lost, the session ends (whoami → api(),
    /// onAuthLost); otherwise it starts again after 1, 2, 4 … 60 s with jitter, while the app is
    /// in front. A running sync resets the count.
    private func syncStateChanged(_ state: SyncServiceState) {
        syncState = state
        switch state {
        case .running:
            restartAttempt = 0
            restartTask?.cancel()
        case .error, .terminated:
            guard inForeground, restartTask == nil || restartTask?.isCancelled == true else { return }
            let delay = min(60, pow(2, Double(restartAttempt))) * Double.random(in: 0.8...1.2)
            restartAttempt += 1
            log.info("sync stopped; restart in \(delay, format: .fixed(precision: 1)) s")
            restartTask = Task { [weak self] in
                if case .error = state { _ = try? await self?.api("GET", "/_matrix/client/v3/account/whoami") }
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.inForeground else { return }
                self.restartTask = nil
                await self.syncService?.start()
            }
        default:
            break
        }
    }

    /// The app went to the background: stop syncing, as Element X does (iOS cuts the connection
    /// anyway, and a dead long-poll is what left the app without updates).
    func enterBackground() async {
        inForeground = false
        restartTask?.cancel()
        restartTask = nil
        await syncService?.stop()
    }

    /// The app is in front again: sync at once, and look at what changed meanwhile.
    func enterForeground() async {
        inForeground = true
        restartAttempt = 0
        await syncService?.start()
        mentions.reload()
    }

    /// Finds the Blog room (joining it if needed, it is open to everyone) and the #one room,
    /// whose presence among the joined rooms makes someone a member. A lapsed membership drops
    /// the room and locks #one-Chat on the next sync.
    private func resolveRooms() async {
        if let blog = await resolve(Self.alias("IPHONEBLOG_BLOG_ALIAS", Brand.blogRoomAlias)) {
            blogRoomID = blog.roomId
            router.blogRoomID = blog.roomId
            rooms.hidden = [blog.roomId]
            // Everyone signed in reads the Blog room; it is public, so join it once.
            if (try? client.getRoom(roomId: blog.roomId)) == nil {
                _ = try? await client.joinRoomById(roomId: blog.roomId)
            }
        } else {
            log.error("blog room alias does not resolve")
        }
        oneRoomID = await resolve(Self.alias("IPHONEBLOG_ONE_ALIAS", Brand.oneRoomAlias))?.roomId
        oneChannelID = await resolve(Self.alias("IPHONEBLOG_CHANNEL_ALIAS", Brand.oneChannelAlias))?.roomId
        await refreshMembership()
        // The space may not have synced yet at this first look, and the room list may then go
        // quiet: look again a few times soon, rather than waiting for the 5-minute timer.
        membershipRetry = Task { [weak self] in
            for delay in [2, 5, 10, 20, 40] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, !self.isOneMember else { return }
                await self.refreshMembership()
            }
        }
        // The bot invites and removes; every change in the room list is a moment to look again,
        // and a slow timer catches an invite that arrives while nothing else moves.
        membershipWatch = rooms.$rooms
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { await self?.refreshMembership() } }
        // The tab badges and each room's mention count follow the room list and @Mentions.
        badgeWatch = rooms.$rooms.combineLatest(mentions.$items, $isOneMember)
            .receive(on: RunLoop.main)
            .sink { [weak self] rooms, items, member in
                guard let self else { return }
                let byRoom = items.filter(\.unread).reduce(into: [String: Int]()) { $0[$1.roomID, default: 0] += 1 }
                self.rooms.serverMentions = byRoom
                // Every #one room counts towards the #one-Chat badge.
                let channels = self.rooms.channelIDs
                let chat = member ? rooms.filter { channels.contains($0.id) }.reduce(0) { $0 + $1.unreadMessages } : 0
                let unread = items.filter(\.unread).count
                if router.chatBadge != chat { router.chatBadge = chat }
                if router.mentionsBadge != unread { router.mentionsBadge = unread }
            }
        membershipTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.refreshMembership()
            }
        }
    }

    /// #one membership is the space #one (2026-11-14_interfaces.md, "Matrix Blog feed"): a member
    /// is joined or invited. Invites to the space and its children are accepted here, and
    /// #one-Chat lists exactly the space's children.
    func refreshMembership() async {
        guard let one = oneRoomID, let space = try? client.getRoom(roomId: one) else {
            setMembership(false, channels: [])
            return
        }
        switch space.membership() {
        case .invited:
            _ = try? await client.joinRoomById(roomId: one)
        case .joined:
            break
        default:
            setMembership(false, channels: [])
            return
        }
        var children: Set<String> = []
        var order: [String] = []
        if let list = try? await client.spaceService().spaceRoomList(spaceId: one) {
            try? await list.paginate()
            for child in await list.rooms() {
                children.insert(child.roomId)
                order.append(child.roomId)
                if child.state == .invited || child.state == nil {
                    _ = try? await client.joinRoomById(roomId: child.roomId)
                }
            }
        }
        spaceOrder = order
        setMembership(true, channels: children)
    }

    /// Fetches the #one room list (names, order, locked for non-members); without the server's
    /// endpoint (the test server), the space's children as the joined rooms name them.
    func loadOneRooms() async {
        struct Response: Decodable {
            struct Room: Decodable {
                let room_id: String // swiftlint:disable:this identifier_name
                let name: String
                let topic: String?
                let locked: Bool?
            }
            let rooms: [Room]
        }
        if let data = try? await api("GET", "/_iphoneblog/v1/rooms"),
           let response = try? JSONDecoder().decode(Response.self, from: data) {
            let list = response.rooms.map { OneRoom(id: $0.room_id, name: $0.name, topic: $0.topic, locked: $0.locked ?? !isOneMember) }
            if list != oneRooms { oneRooms = list }
            return
        }
        let ids = spaceOrder.isEmpty ? rooms.channelIDs.sorted() : spaceOrder
        let list = ids.map { id in
            OneRoom(id: id, name: rooms.rooms.first { $0.id == id }?.name ?? ((try? client.getRoom(roomId: id))?.displayName() ?? id),
                    topic: nil, locked: !isOneMember)
        }
        if list != oneRooms { oneRooms = list }
    }

    private func setMembership(_ member: Bool, channels: Set<String>) {
        // The channel alias may not resolve (an older server); then the space's first child.
        if oneChannelID == nil || !(channels.isEmpty || channels.contains(oneChannelID!)) { // swiftlint:disable:this force_unwrapping
            if let first = channels.sorted().first { oneChannelID = first }
        }
        if member != isOneMember { isOneMember = member }
        if router.isMember != member { router.isMember = member }
        if rooms.channelIDs != channels { rooms.channelIDs = channels }
    }

    /// Resolves an alias of this account's own server. Another server's alias would send the
    /// homeserver over federation, which can take minutes to give up; the app has none.
    private func resolve(_ alias: String) async -> ResolvedRoomAlias? {
        guard alias.split(separator: ":").last == userID.split(separator: ":").last else {
            log.error("alias \(alias, privacy: .public) is not on this server")
            return nil
        }
        return try? await client.resolveRoomAlias(roomAlias: alias)
    }

    /// Room aliases from brand.env; debug runs against a test server may name others.
    private static func alias(_ key: String, _ fallback: String) -> String {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { return value }
        #endif
        return fallback
    }

    deinit {
        membershipTimer?.cancel()
        membershipRetry?.cancel()
    }

    func stop() async {
        authGuard.cancel()
        await syncService?.stop()
    }

    // MARK: - ChatHost

    func openThread(roomID: String, rootEventID: String) {
        router.openThread(roomID: roomID, rootEventID: rootEventID)
    }

    func openUser(userID: String) {
        router.profile = Router.Person(userID: userID, shareNow: false)
    }

    func shareContact(userID: String) {
        guard router.isMember, ContactShare.canShare(with: userID, me: self.userID) else { return }
        router.profile = Router.Person(userID: userID, shareNow: true)
    }

    func openRoom(roomID: String) {
        router.openRoom(roomID)
    }

    func openURL(_ url: URL) {
        if let link = ChatLink.parse(url) {
            Task { await open(link) }
            return
        }
        router.presentedURL = url
    }

    /// A chat link: a thread reply opens its thread, any other message its room, scrolled to and
    /// highlighted; a room link the room. The link names no thread, so the event says (as the
    /// web chat does). The thread screen does not scroll to a reply yet.
    func open(_ link: ChatLink) async {
        let roomID: String
        if link.room.hasPrefix("#") {
            guard let resolved = await resolve(link.room) else {
                router.notice = "Diesen Raum gibt es nicht."
                return
            }
            roomID = resolved.roomId
        } else {
            roomID = link.room
        }
        guard let eventID = link.eventID else {
            router.openRoom(roomID)
            return
        }
        if let root = await threadRoot(of: eventID, in: roomID) {
            router.openThread(roomID: roomID, rootEventID: root)
        } else {
            router.openMessage(roomID: roomID, eventID: eventID)
        }
    }

    /// The thread an event replies in, from the event itself (GET /rooms/{id}/event/{id}).
    private func threadRoot(of eventID: String, in roomID: String) async -> String? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let room = roomID.addingPercentEncoding(withAllowedCharacters: allowed),
              let event = eventID.addingPercentEncoding(withAllowedCharacters: allowed),
              let data = try? await api("GET", "/_matrix/client/v3/rooms/\(room)/event/\(event)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let relates = (json["content"] as? [String: Any])?["m.relates_to"] as? [String: Any],
              relates["rel_type"] as? String == "m.thread" else { return nil }
        return relates["event_id"] as? String
    }

    func didSee(roomID: String, threadRootEventID: String?, eventID: String) {
        Task { await mentions.didSee(roomID: roomID, threadRoot: threadRootEventID, eventID: eventID) }
    }

    func showMessage(_ text: String) {
        router.notice = text
    }

    // MARK: - Block and report

    /// Blocked people (Matrix "ignored users"): their messages no longer reach this account.
    func isBlocked(_ userID: String) async -> Bool {
        (try? await client.ignoredUsers())?.contains(userID) ?? false
    }

    func setBlocked(_ userID: String, _ on: Bool) async throws {
        if on { try await client.ignoreUser(userId: userID) } else { try await client.unignoreUser(userId: userID) }
    }

    /// Reports a person to the server's admins (POST /users/{id}/report, Matrix 1.14).
    func reportUser(_ userID: String, reason: String) async throws {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let user = userID.addingPercentEncoding(withAllowedCharacters: allowed) else { throw URLError(.badURL) }
        let body = try JSONSerialization.data(withJSONObject: ["reason": reason.isEmpty ? "Gemeldet in der iPhoneBlog-App" : reason])
        _ = try await api("POST", "/_matrix/client/v3/users/\(user)/report", body: body)
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

    /// A client-server API call the SDK has no method for, with this session's token.
    /// After a 5xx answer or a network error the app's own calls hold back, 1 s doubling to 60 s
    /// with jitter, so a restarting server is not hit by every model at once (68 calls in one
    /// minute during a Synapse restart).
    private var apiPausedUntil = Date.distantPast
    private var apiFailures = 0

    func api(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        if Date() < apiPausedUntil { throw URLError(.cannotConnectToHost) }
        do {
            let data: Data
            let sent = Date()
            do {
                data = try await apiCall(method, path, body: body)
            } catch TokenRefused.unknownToken {
                // Our calls take the token as it is; the SDK refreshes it. Check, then once more.
                guard await authGuard.confirmValid(path: path, requestSent: sent) else { throw URLError(.userAuthenticationRequired) }
                data = try await apiCall(method, path, body: body)
            }
            apiFailures = 0
            return data
        } catch let error as URLError where error.code != .badServerResponse || lastStatus >= 500 {
            apiFailures += 1
            apiPausedUntil = Date().addingTimeInterval(min(60, pow(2, Double(apiFailures - 1))) * Double.random(in: 0.8...1.2))
            throw error
        }
    }

    private var lastStatus = 0

    private enum TokenRefused: Error { case unknownToken }

    /// What AuthGuard asks: one SDK request that refreshes the token when due (the user
    /// directory needs a token), whoami with the token as it is now, and whether MAS answers.
    private var authProbes: AuthGuard.Probes {
        AuthGuard.Probes(
            sdkRequest: { [client, userID] in
                do {
                    _ = try await client.searchUsers(searchTerm: MentionsModel.localpart(userID), limit: 1)
                    return nil
                } catch {
                    return String(describing: error)
                }
            },
            whoami: { [client] in
                let base = client.homeserver().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: base + "/_matrix/client/v3/account/whoami"),
                      let token = try? client.session().accessToken else { return nil }
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
                return (status, data)
            },
            issuerUp: {
                let issuer = Brand.oauthIssuerURL.hasSuffix("/") ? Brand.oauthIssuerURL : Brand.oauthIssuerURL + "/"
                guard let url = URL(string: issuer + ".well-known/openid-configuration") else { return false }
                let request = URLRequest(url: url, timeoutInterval: 15)
                guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
                return (response as? HTTPURLResponse)?.statusCode == 200
            })
    }

    /// One call to our own endpoints, with the HTTP status for the caller to read (no backoff):
    /// "Kontaktdaten teilen" tells each refusal apart.
    func call(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, Int) {
        let sent = Date()
        let answer = try await callOnce(method, path, body: body)
        // A stale token: AuthGuard checks (the SDK refreshes), then one more try (as api()).
        guard answer.1 == 401, String(data: answer.0.prefix(300), encoding: .utf8)?.contains("M_UNKNOWN_TOKEN") == true,
              await authGuard.confirmValid(path: path, requestSent: sent) else { return answer }
        return try await callOnce(method, path, body: body)
    }

    private func callOnce(_ method: String, _ path: String, body: Data?) async throws -> (Data, Int) {
        let base = client.homeserver().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try client.session().accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func apiCall(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        let base = client.homeserver().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try client.session().accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        lastStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 401,
               String(data: data.prefix(300), encoding: .utf8)?.contains("M_UNKNOWN_TOKEN") == true {
                throw TokenRefused.unknownToken
            }
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Profile picture

    /// The picture behind the account's avatar URL, as a thumbnail.
    func loadAvatar() async {
        guard let url = try? await client.avatarUrl(), let source = try? MediaSource.fromUrl(url: url),
              let data = try? await client.getMediaThumbnail(mediaSource: source, width: 240, height: 240) else {
            avatar = nil
            return
        }
        avatar = UIImage(data: data)
    }

    /// Sets the profile picture: square, at most 512 points, JPEG. The display name stays the
    /// blog's; only the picture is the person's own choice.
    func setAvatar(_ image: UIImage) async throws {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let target = CGSize(width: min(side, 512), height: min(side, 512))
        let square = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(x: -crop.minX * target.width / side, y: -crop.minY * target.height / side,
                                  width: image.size.width * target.width / side, height: image.size.height * target.height / side))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { return }
        try await client.uploadAvatar(mimeType: "image/jpeg", data: data)
        avatar = square
    }

    func removeAvatar() async throws {
        try await client.removeAvatar()
        avatar = nil
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
