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
    /// "Für dich": mentions, threads you are in, rooms with news.
    let forYou = ForYouModel()
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
    struct OneRoom: Identifiable, Equatable, Codable {
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
        StartTrace.mark("session start")
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
            StartTrace.mark("sync service built")
        }
        await syncService?.start()
        StartTrace.mark("sync started")
        // **A warm launch** shows what the phone knows at once: the rooms, membership and the
        // #one list from the last run (WarmStart), the timelines from the SDK's event cache.
        // The server's answers replace them in the background; no spinner waits for a round
        // trip (2026-11-20, docs/performance.md). A first launch, or a new account, waits.
        let warm = startedOnce ? nil : WarmStart.load(for: userID)
        startedOnce = true
        if let warm {
            apply(warm)
            StartTrace.mark("warm start applied")
        } else {
            await resolveRooms()
            StartTrace.mark("rooms resolved")
        }
        try await ChatScreens.provider.start(host: self)
        StartTrace.mark("chat screens ready")
        mentions.attach(to: self)
        forYou.attach(to: self)
        notificationPrefs.attach(to: self)
        // The #one rooms, the bots, the name and the picture load beside the screens, not before
        // them: each is a round trip, and the app showed a spinner for all of them in a row,
        // about a second on a phone before #one could open a room (2026-11-20, docs/performance.md).
        Task { [weak self] in
            guard let self else { return }
            if warm != nil { await resolveRooms() }
            await loadOneRooms()
            saveWarmStart()
            StartTrace.fresh()
        }
        Task { [weak self] in
            guard let self else { return }
            await loadBots()
            displayName = try? await client.displayName()
            await loadAvatar()
        }
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
        // The three addresses at once: one after another they cost three round trips.
        async let blogAlias = resolve(Self.alias("IPHONEBLOG_BLOG_ALIAS", Brand.blogRoomAlias))
        async let oneAlias = resolve(Self.alias("IPHONEBLOG_ONE_ALIAS", Brand.oneRoomAlias))
        async let channelAlias = resolve(Self.alias("IPHONEBLOG_CHANNEL_ALIAS", Brand.oneChannelAlias))
        if let blog = await blogAlias {
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
        oneRoomID = await oneAlias?.roomId
        oneChannelID = await channelAlias?.roomId
        StartTrace.mark("aliases")
        await refreshMembership()
        StartTrace.mark("membership")
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
        badgeWatch = rooms.$rooms.combineLatest(mentions.$items, $isOneMember, forYou.$threads)
            .receive(on: RunLoop.main)
            .sink { [weak self] rooms, items, member, threads in
                guard let self else { return }
                let byRoom = items.filter(\.unread).reduce(into: [String: Int]()) { $0[$1.roomID, default: 0] += 1 }
                self.rooms.serverMentions = byRoom
                // Every #one room counts towards the #one-Chat badge.
                let channels = self.rooms.channelIDs
                let chat = member ? rooms.filter { channels.contains($0.id) }.reduce(0) { $0 + $1.unreadMessages } : 0
                // Für dich: unread mentions and threads with new replies.
                let unread = items.filter(\.unread).count + threads.filter(\.isUnread).count
                if router.chatBadge != chat { router.chatBadge = chat }
                if router.forYouBadge != unread { router.forYouBadge = unread }
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
        // Start-up and the #one tab both ask; the second waits for the first.
        if let running = oneRoomsLoad { return await running.value }
        let load = Task { await fetchOneRooms() }
        oneRoomsLoad = load
        await load.value
        oneRoomsLoad = nil
    }

    private var oneRoomsLoad: Task<Void, Never>?

    private func fetchOneRooms() async {
        StartTrace.mark("one rooms: load")
        defer { StartTrace.mark("one rooms: loaded \(oneRooms.count)") }
        struct Response: Decodable {
            struct Room: Decodable {
                let room_id: String // swiftlint:disable:this identifier_name
                // Rooms come from the space #one since 2026-11-20; one made in Element may have
                // no name (the server sends "") and no alias (the app never reads alias).
                let name: String?
                let topic: String?
                let locked: Bool?
            }
            let rooms: [Room]
        }
        if let data = try? await api("GET", "/_iphoneblog/v1/rooms"),
           let response = try? JSONDecoder().decode(Response.self, from: data) {
            let list = response.rooms.map { room in
                let given = room.name.flatMap { $0.isEmpty ? nil : $0 }
                let shown = given ?? (try? client.getRoom(roomId: room.room_id))?.displayName().flatMap { $0.isEmpty ? nil : $0 } ?? room.room_id
                return OneRoom(id: room.room_id, name: shown, topic: room.topic.flatMap { $0.isEmpty ? nil : $0 },
                               locked: room.locked ?? !isOneMember)
            }
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

    /// The last run's rooms and membership, for a warm launch (WarmStart).
    private var startedOnce = false

    private func apply(_ warm: WarmStart) {
        if let blog = warm.blogRoomID {
            blogRoomID = blog
            router.blogRoomID = blog
            rooms.hidden = [blog]
        }
        oneRoomID = warm.oneRoomID
        oneChannelID = warm.oneChannelID
        spaceOrder = warm.spaceOrder
        setMembership(warm.isMember, channels: Set(warm.channels))
        if warm.oneRooms != oneRooms { oneRooms = warm.oneRooms }
    }

    /// Kept after every fresh look at the server, so the next launch starts from it.
    private func saveWarmStart() {
        WarmStart(blogRoomID: blogRoomID, oneRoomID: oneRoomID, oneChannelID: oneChannelID, isMember: isOneMember,
                  channels: rooms.channelIDs.sorted(), spaceOrder: spaceOrder, oneRooms: oneRooms).save(for: userID)
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
        if let user = ChatLink.userID(url) {
            openUser(userID: user)
            return
        }
        if let link = ChatLink.parse(url) {
            Task { await open(link) }
            return
        }
        router.presentedURL = url
    }

    /// A chat link: a thread reply opens its thread, any other message its room, scrolled to and
    /// highlighted; a room link the room. The link names no thread, so the event says (as the
    /// web chat does). A thread opens on the linked reply; a Blog thread in the Blog tab.
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
            // The thread opens on the linked reply, not where the reader stopped.
            if !router.isOnScreen(roomID: roomID, threadRootEventID: root) {
                ChatScreens.provider.focus(roomID: roomID, threadRootEventID: root, eventID: eventID)
            }
            router.openThread(roomID: roomID, rootEventID: root)
        } else {
            router.openMessage(roomID: roomID, eventID: eventID)
        }
    }

    /// The thread an event replies in, from the event itself (GET /rooms/{id}/event/{id}).
    /// The root of the thread `eventID` is a reply in, from its m.thread relation; nil for an
    /// event in no thread (a root among them) and when the event cannot be fetched.
    func threadRoot(of eventID: String, in roomID: String) async -> String? {
        guard case .some(.some(let root)) = await threadRelation(of: eventID, in: roomID) else { return nil }
        return root
    }

    /// nil: the server could not be asked. .some(nil): the event is in no thread. .some(root):
    /// a reply in the thread of `root`.
    func threadRelation(of eventID: String, in roomID: String) async -> String?? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let room = roomID.addingPercentEncoding(withAllowedCharacters: allowed),
              let event = eventID.addingPercentEncoding(withAllowedCharacters: allowed),
              let data = try? await api("GET", "/_matrix/client/v3/rooms/\(room)/event/\(event)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let relates = (json["content"] as? [String: Any])?["m.relates_to"] as? [String: Any],
              relates["rel_type"] as? String == "m.thread" else { return .some(nil) }
        return .some(relates["event_id"] as? String)
    }

    func isOnScreen(roomID: String, threadRootEventID: String?) -> Bool {
        router.isOnScreen(roomID: roomID, threadRootEventID: threadRootEventID)
    }

    func didSee(roomID: String, threadRootEventID: String?, eventID: String, isPrivate: Bool) {
        Task { await mentions.didSee(roomID: roomID, threadRoot: threadRootEventID, eventID: eventID) }
        if threadRootEventID == nil {
            Task { await catchUpUnthreadedReceipt(roomID: roomID, eventID: eventID, isPrivate: isPrivate) }
        }
    }

    // MARK: GIFs aus dem Chat

    /// #one rooms and their threads, for #one members; never the Blog room (gif-library.md).
    func offersGIFs(roomID: String) -> Bool {
        isOneMember && roomID != blogRoomID && oneRooms.contains { $0.id == roomID }
    }

    func pickGIF(roomID: String, send: @escaping @MainActor (_ mxc: String, _ width: Int?, _ height: Int?, _ size: Int?) -> Void) {
        router.gifPick = GIFPickRequest(roomID: roomID) { gif in send(gif.mxc, gif.width, gif.height, gif.size) }
    }

    func gifNeedsTags(sha256: String) async -> Bool {
        guard isOneMember else { return false }
        return (try? await GIFLibraryAPI(session: self).lookup(sha256: sha256).needsTag) ?? false
    }

    func tagGIF(sha256: String, tags: [String]) async {
        _ = try? await GIFLibraryAPI(session: self).addTags(tags, to: sha256)
    }

    func parseGIFTags(_ text: String) -> (tags: [String], problem: String?) {
        switch GIFTags.parse(text) {
        case .success(let tags): (tags, nil)
        case .failure(.badTag(let why)): ([], why)
        case .failure: ([], "Die Schlagworte stimmen nicht.")
        }
    }

    func showMessage(_ text: String) {
        router.notice = text
    }

    // MARK: - Bots

    /// The accounts the chat server lists as bots (GET /_iphoneblog/v1/bots): marked "Bot" in the
    /// timeline. Debug runs against a test server may name them (IPHONEBLOG_BOTS).
    func loadBots() async {
        #if DEBUG
        if let list = ProcessInfo.processInfo.environment["IPHONEBLOG_BOTS"], !list.isEmpty {
            ChatScreens.provider.setBots(Set(list.split(separator: ",").map(String.init)))
            return
        }
        #endif
        let base = client.homeserver().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/_iphoneblog/v1/bots"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bots = json["bots"] as? [String] else { return }
        ChatScreens.provider.setBots(Set(bots))
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
        } catch let error as URLError where Self.countsAsOutage(error.code, status: lastStatus) {
            apiFailures += 1
            apiPausedUntil = Date().addingTimeInterval(min(60, pow(2, Double(apiFailures - 1))) * Double.random(in: 0.8...1.2))
            throw error
        }
    }

    private var lastStatus = 0
    /// The HTTP status of the last `api` call, so a caller can tell 403 from 429 (GIFLibraryAPI).
    var lastAPIStatus: Int { lastStatus }

    /// What pauses our calls (the backoff): the server or the network failing, not a request
    /// the app itself cancelled (search cancels one per keystroke: "Comics" typed letter by
    /// letter paused every call for up to a minute, "Die Suche ist gerade nicht erreichbar"),
    /// not a token check, and not a 4xx answer.
    nonisolated static func countsAsOutage(_ code: URLError.Code, status: Int) -> Bool {
        switch code {
        case .cancelled, .userAuthenticationRequired: return false
        case .badServerResponse: return status >= 500
        default: return true
        }
    }

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

    /// Sets the profile picture from the placed square (AvatarCrop): the JPEG goes to the media
    /// store with its progress reported, then the profile points at it. The display name stays
    /// the blog's; only the picture is the person's own choice.
    func setAvatar(jpeg: Data, image: UIImage, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        #if DEBUG
        // UI tests see the progress on a local server that takes 50 KB at once.
        if let delay = ProcessInfo.processInfo.environment["IPHONEBLOG_AVATAR_UPLOAD_DELAY"].flatMap(Double.init) {
            progress(0)
            try await Task.sleep(for: .seconds(delay))
        }
        #endif
        let base = client.homeserver().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/_matrix/media/v3/upload?filename=avatar.jpg") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try client.session().accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: jpeg, delegate: UploadProgress(progress))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let uri = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["content_uri"] as? String else {
            throw URLError(.badServerResponse)
        }
        let user = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? userID
        _ = try await api("PUT", "/_matrix/client/v3/profile/\(user)/avatar_url",
                          body: JSONSerialization.data(withJSONObject: ["avatar_url": uri]))
        progress(1)
        avatar = image
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

/// Reports how much of an upload has gone out, on the main actor.
private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @MainActor @Sendable (Double) -> Void
    init(_ report: @escaping @MainActor @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let share = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in report(min(0.99, share)) }
    }
}

/// What a warm launch shows before the server answers: the last run's room IDs, #one
/// membership and the #one list, per account in UserDefaults. Room IDs and names only, nothing
/// personal (the privacy rule: no personal data kept beyond email, nickname and pictures).
struct WarmStart: Codable, Equatable {
    var blogRoomID: String?
    var oneRoomID: String?
    var oneChannelID: String?
    var isMember: Bool
    var channels: [String]
    var spaceOrder: [String]
    var oneRooms: [ChatSession.OneRoom]

    private static func key(_ userID: String) -> String { "warmStart." + userID }

    static func load(for userID: String) -> WarmStart? {
        guard let data = UserDefaults.standard.data(forKey: key(userID)) else { return nil }
        return try? JSONDecoder().decode(WarmStart.self, from: data)
    }

    func save(for userID: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(userID))
    }

    static func forget(for userID: String) { UserDefaults.standard.removeObject(forKey: key(userID)) }
}

