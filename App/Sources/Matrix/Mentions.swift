import Combine
import Foundation
import MatrixRustSDK
import OSLog
import UIKit

/// @Mentions (preview 4): every event that mentions me, newest first, from the server's
/// notification list (`GET /notifications?only=highlight`). The server keeps it across devices
/// and marks an entry read once my read receipt passes it.
@MainActor
final class MentionsModel: ObservableObject {
    struct Mention: Identifiable, Equatable {
        enum Place: Equatable {
            /// A #one room, by its name; `threadRoot` when it was said in a thread.
            case channel(roomID: String, threadRoot: String?, name: String?)
            /// The discussion under an article.
            case discussion(rootEventID: String, title: String?)
            /// Anywhere else the account is joined.
            case room(roomID: String, name: String?)
        }

        let id: String
        /// The room it was said in, whatever the place.
        let roomID: String
        let place: Place
        let senderID: String
        var senderName: String
        let body: String
        let date: Date
        /// The thread it was said in, if any.
        let threadRoot: String?
        /// No receipt of this account at or after it ("read up to here", Thorsten's decision A,
        /// 2026-11-17); see `withReadState`.
        var unread: Bool
    }

    @Published private(set) var items: [Mention] = []
    @Published private(set) var hasLoaded = false
    var unreadCount: Int { items.filter(\.unread).count }

    private weak var session: ChatSession?
    private var names: [String: String] = [:]
    private var watch: AnyCancellable?
    private var loading: Task<Void, Never>?
    private let log = Logger(subsystem: Brand.bundleID, category: "mentions")

    /// Loads now and again whenever the room list moves (a new message, a read receipt).
    func attach(to session: ChatSession) {
        self.session = session
        // Only when a room's unread counts move: a new message or a read receipt, not every
        // room-list update (perf review, 2026-11-16).
        watch = session.rooms.$rooms
            .map { rooms in rooms.map { "\($0.id):\($0.unreadMessages):\($0.sdkMentions)" } }
            .removeDuplicates()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
        reload()
    }

    /// "Alle als gelesen" (Thorsten, 2026-11-17: in build 133 it did nothing for thread replies).
    /// Receipts for exactly what the list shows, under "read up to here": per thread a threaded
    /// receipt on its newest unread mention, per room's own timeline a "main" one on its newest
    /// unread mention, as the web chat sends them. Failures are said, and the list reloads.
    func markAllRead() async {
        guard let session else { return }
        let unread = items.filter(\.unread)
        guard !unread.isEmpty else { return }
        let receipts = Self.receipts(for: unread)
        items = items.map { var mention = $0; mention.unread = false; return mention }
        let background = UIApplication.shared.beginBackgroundTask(withName: "mentions-read")
        var failed = 0
        for receipt in receipts {
            do {
                _ = try await session.api("POST", receipt.path, body: receipt.body)
            } catch {
                failed += 1
            }
        }
        UIApplication.shared.endBackgroundTask(background)
        if failed > 0 {
            session.router.notice = "Nicht alles ließ sich als gelesen markieren. Versuch es gleich noch einmal."
            log.error("mark all read: \(failed, privacy: .public) of \(receipts.count, privacy: .public) receipts failed")
        }
        try? await Task.sleep(for: .seconds(1))
        reload()
    }

    struct Receipt: Equatable {
        let path: String
        let body: Data
    }

    /// The receipts that mark these mentions read: newest per thread, newest per room timeline.
    nonisolated static func receipts(for mentions: [Mention]) -> [Receipt] {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        func path(_ room: String, _ event: String) -> String? {
            guard let room = room.addingPercentEncoding(withAllowedCharacters: allowed),
                  let event = event.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return "/_matrix/client/v3/rooms/\(room)/receipt/m.read/\(event)"
        }
        func body(_ thread: String?) -> Data {
            (try? JSONSerialization.data(withJSONObject: thread.map { ["thread_id": $0] } ?? [:])) ?? Data("{}".utf8)
        }
        var newest: [String: Mention] = [:] // key: room + thread ("main" for the timeline)
        for mention in mentions {
            let key = mention.roomID + "|" + (mention.threadRoot ?? "main")
            if let known = newest[key], known.date >= mention.date { continue }
            newest[key] = mention
        }
        var result: [Receipt] = []
        for (_, mention) in newest.sorted(by: { $0.key < $1.key }) {
            guard let path = path(mention.roomID, mention.id) else { continue }
            if let root = mention.threadRoot {
                result.append(Receipt(path: path, body: body(root)))
            } else {
                result.append(Receipt(path: path, body: body("main")))
            }
        }
        return result
    }

    /// A timeline sent a read receipt (ChatKitReads.seen). The server marks the mentions up to
    /// it read, in a room and in a thread; the list reloads, once soon and once when the receipt
    /// has surely landed, so the badge follows without waiting for a room count to move.
    func didSee(roomID: String, threadRoot: String?, eventID: String) async {
        for delay in [1.0, 3.0] {
            try? await Task.sleep(for: .seconds(delay))
            reload()
        }
    }

    // MARK: Read state

    /// Read or not, from the account's own receipts, as the web chat does. Synapse's own read flag
    /// in /notifications is not usable: it takes one receipt row per room, whichever the database
    /// returns last, of any thread (receipts.py, _get_receipts_for_user_with_orderings; measured by
    /// the web session, 2026-11-17). A mention is read once a receipt of this account (public or
    /// private, any device) is at or after it: the thread's or the unthreaded one for a thread
    /// reply, the main timeline's or the unthreaded one for a room message. "At or after" compares
    /// the server times of the two events.
    private var eventTimes: [String: Date] = [:]

    private func withReadState(_ mentions: [Mention], session: ChatSession) async -> [Mention] {
        var newest: [String: Date] = [:] // "room|thread" → time of the newest receipted event
        func receiptTime(room: Room, roomID: String, thread: ReceiptThread, key: String) async -> Date? {
            if let known = newest[key] { return known == .distantPast ? nil : known }
            var best: Date?
            for type in [ReceiptType.read, .readPrivate] {
                guard let receipt = try? await room.loadUserReceipt(receiptType: type, thread: thread, userId: session.userID),
                      let time = await eventTime(receipt.eventId, roomID: roomID, session: session) else { continue }
                best = max(best ?? time, time)
            }
            newest[key] = best ?? .distantPast
            return best
        }
        var result: [Mention] = []
        for var mention in mentions {
            guard let room = try? session.client.getRoom(roomId: mention.roomID) else {
                result.append(mention)
                continue
            }
            let own: (ReceiptThread, String) = mention.threadRoot.map { (.thread(threadRootEventId: $0), $0) } ?? (.main, "main")
            var read = false
            for (thread, name) in [own, (.unthreaded, "unthreaded")] where !read {
                if let time = await receiptTime(room: room, roomID: mention.roomID, thread: thread, key: mention.roomID + "|" + name) {
                    read = time >= mention.date
                }
            }
            mention.unread = !read
            result.append(mention)
        }
        return result
    }

    /// An event's server time, from @Mentions itself or the server, kept for the app's run.
    func eventTime(_ eventID: String, roomID: String, session: ChatSession) async -> Date? {
        if let known = eventTimes[eventID] { return known }
        if let listed = items.first(where: { $0.id == eventID }) { return listed.date }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let room = roomID.addingPercentEncoding(withAllowedCharacters: allowed),
              let event = eventID.addingPercentEncoding(withAllowedCharacters: allowed),
              let data = try? await session.api("GET", "/_matrix/client/v3/rooms/\(room)/event/\(event)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = json["origin_server_ts"] as? Double else { return nil }
        let date = Date(timeIntervalSince1970: ts / 1000)
        eventTimes[eventID] = date
        return date
    }

    func reload() {
        loading?.cancel()
        loading = Task { await load() }
    }

    private func load() async {
        guard let session else { return }
        do {
            let data = try await session.api("GET", "/_matrix/client/v3/notifications?only=highlight&limit=50")
            let page = try JSONDecoder().decode(NotificationPage.self, from: data)
            var result: [Mention] = []
            for entry in page.notifications {
                guard let mention = await mention(from: entry, session: session) else { continue }
                result.append(mention)
            }
            result = await withReadState(result, session: session)
            guard !Task.isCancelled else { return }
            if result != items { items = result }
            hasLoaded = true
        } catch {
            if !Task.isCancelled { log.error("mentions failed: \(error.localizedDescription, privacy: .public)") }
            hasLoaded = true
        }
    }

    private func mention(from entry: NotificationPage.Entry, session: ChatSession) async -> Mention? {
        let event = entry.event
        guard event.sender != session.userID, let raw = event.content?.body else { return nil }
        // Any client's message as plain text, mentions as "@Name" (PushText, the one preview helper).
        let body = PushText.plain(body: raw, formattedBody: event.content?.formattedBody)
        // No direct messages in this app (Thorsten, 2026-11-16): a mention in one stays out.
        if session.rooms.rooms.first(where: { $0.id == entry.roomId })?.isDirect == true { return nil }
        let thread = event.content?.relatesTo?.relType == "m.thread" ? event.content?.relatesTo?.eventId : nil
        let place: Mention.Place
        if entry.roomId == session.blogRoomID {
            guard let root = thread else { return nil }
            let title = await threadTitle(root)
            place = .discussion(rootEventID: root, title: title)
        } else if session.rooms.channelIDs.contains(entry.roomId) {
            let name = session.oneRooms.first { $0.id == entry.roomId }?.name
                ?? session.rooms.rooms.first { $0.id == entry.roomId }?.name
            place = .channel(roomID: entry.roomId, threadRoot: thread, name: name)
        } else {
            place = .room(roomID: entry.roomId, name: try? session.client.getRoom(roomId: entry.roomId)?.displayName())
        }
        return Mention(id: event.eventId, roomID: entry.roomId, place: place, senderID: event.sender,
                       senderName: await name(of: event.sender, session: session),
                       body: body, date: Date(milliseconds: event.originServerTs ?? entry.ts),
                       threadRoot: thread, unread: !entry.read)
    }

    /// An article's title by its thread root, fetched once per app run.
    private var titles: [String: String] = [:]
    private func threadTitle(_ root: String) async -> String? {
        if let known = titles[root] { return known }
        guard let title = try? await DiscussionStore.shared.thread(root).root.title else { return nil }
        titles[root] = title
        return title
    }

    func name(of userID: String, session: ChatSession) async -> String {
        if let known = names[userID] { return known }
        let name = (try? await session.client.getProfile(userId: userID))?.displayName ?? Self.localpart(userID)
        names[userID] = name
        return name
    }

    nonisolated static func localpart(_ userID: String) -> String {
        String(userID.dropFirst().prefix { $0 != ":" })
    }

    private struct NotificationPage: Decodable {
        struct Entry: Decodable {
            let event: Event
            let read: Bool
            let roomId: String
            let ts: Int64

            enum CodingKeys: String, CodingKey { case event, read, roomId = "room_id", ts }
        }

        struct Event: Decodable {
            let eventId: String
            let sender: String
            let originServerTs: Int64?
            let content: Content?

            enum CodingKeys: String, CodingKey {
                case eventId = "event_id", sender, originServerTs = "origin_server_ts", content
            }
        }

        struct Content: Decodable {
            let body: String?
            let formattedBody: String?
            let relatesTo: Relation?

            enum CodingKeys: String, CodingKey { case body, formattedBody = "formatted_body", relatesTo = "m.relates_to" }
        }

        struct Relation: Decodable {
            let relType: String?
            let eventId: String?

            enum CodingKeys: String, CodingKey { case relType = "rel_type", eventId = "event_id" }
        }

        let notifications: [Entry]
    }
}

/// The switches under "Mitteilungen" on Ich (preview 5a), each one a push rule on the server so
/// every device of the account follows it.
@MainActor
final class NotificationPrefs: ObservableObject {
    enum ChannelMode: String, CaseIterable, Identifiable {
        case all = "Alle"
        case mentions = "Nur Erwähnungen"
        case mute = "Aus"
        var id: String { rawValue }
    }

    @Published private(set) var newArticles = true
    @Published private(set) var mentions = true
    /// Each #one room's push mode; "Nur Erwähnungen" unless someone chose otherwise.
    @Published private(set) var roomModes: [String: ChannelMode] = [:]
    @Published private(set) var hasLoaded = false

    /// An override rule: in the Blog room, an event that carries an article (only the bot posts
    /// those, 2026-11-14_interfaces.md). Replies there stay quiet unless they mention me.
    static let articleRuleID = "de.iphoneblog.new_articles"
    /// Per account: the device-wide flag left a second account on the same phone without the
    /// rule (it stayed "seeded" from the first).
    private static func articleRuleSeeded(_ userID: String) -> String { "articleRuleSeeded.\(userID)" }

    private weak var session: ChatSession?
    private let log = Logger(subsystem: Brand.bundleID, category: "push-rules")

    func attach(to session: ChatSession) {
        self.session = session
        Task { await load() }
    }

    func load() async {
        guard let session else { return }
        let settings = await session.client.getNotificationSettings()
        if let blog = session.blogRoomID {
            // Every reply in the Blog room would ring otherwise.
            if let current = try? await settings.getRoomNotificationSettings(roomId: blog, isEncrypted: false, isOneToOne: false),
               current.isDefault {
                try? await settings.setRoomNotificationMode(roomId: blog, mode: .mentionsAndKeywordsOnly)
            }
            // New articles ring by default, once; after that the switch decides.
            // Builds up to 72 kept one flag for the device; it counts for the account signed in now,
            // so a switch someone turned off stays off.
            if UserDefaults.standard.bool(forKey: "articleRuleSeeded") {
                UserDefaults.standard.set(true, forKey: Self.articleRuleSeeded(session.userID))
                UserDefaults.standard.removeObject(forKey: "articleRuleSeeded")
            }
            if !UserDefaults.standard.bool(forKey: Self.articleRuleSeeded(session.userID)) {
                if (try? await putArticleRule(blogRoomID: blog, session: session)) != nil {
                    UserDefaults.standard.set(true, forKey: Self.articleRuleSeeded(session.userID))
                }
            }
        }
        // Push only for @mentions of me (replies to me carry one) and new articles; every other
        // message is silent and counts towards the badge (testers: "Pusht die ganze Zeit").
        // One account rule, as the server session advised: the default underride for messages
        // goes off, so rooms added later need nothing; a room set to "Alle" gets its own rule.
        // Once per account, marked in its account data (de.iphoneblog.push_defaults), so a choice
        // made later, here or in the web app, is never overwritten.
        if let user = session.userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "@:"))) {
            let marker = "/_matrix/client/v3/user/\(user)/account_data/de.iphoneblog.push_defaults"
            if (try? await session.api("GET", marker)) == nil,
               (try? await session.api("PUT", "/_matrix/client/v3/pushrules/global/underride/.m.rule.message/enabled",
                                       body: Data(#"{"enabled":false}"#.utf8))) != nil {
                _ = try? await session.api("PUT", marker, body: Data(#"{"messages_quiet":true}"#.utf8))
            }
        }
        newArticles = (try? await session.api("GET", "/_matrix/client/v3/pushrules/global/override/\(Self.articleRuleID)")) != nil
        mentions = (try? await settings.isUserMentionEnabled()) ?? true
        var modes: [String: ChannelMode] = [:]
        for roomID in session.rooms.channelIDs {
            guard let current = try? await settings.getRoomNotificationSettings(roomId: roomID, isEncrypted: false, isOneToOne: false) else { continue }
            modes[roomID] = switch current.mode {
            case .allMessages: .all
            case .mentionsAndKeywordsOnly: .mentions
            case .mute: .mute
            }
        }
        roomModes = modes
        hasLoaded = true
    }

    func setNewArticles(_ on: Bool) {
        guard let session, let blog = session.blogRoomID else { return }
        newArticles = on
        Task {
            do {
                if on {
                    try await putArticleRule(blogRoomID: blog, session: session)
                } else {
                    _ = try await session.api("DELETE", "/_matrix/client/v3/pushrules/global/override/\(Self.articleRuleID)")
                }
            } catch {
                log.error("article rule failed: \(error.localizedDescription, privacy: .public)")
                await load()
            }
        }
    }

    func setMentions(_ on: Bool) {
        guard let session else { return }
        mentions = on
        Task {
            let settings = await session.client.getNotificationSettings()
            do {
                try await settings.setUserMentionEnabled(enabled: on)
                try await settings.setRoomMentionEnabled(enabled: on)
            } catch {
                log.error("mention rules failed: \(error.localizedDescription, privacy: .public)")
                await load()
            }
        }
    }

    /// One room's push mode: Alle (its own rule), Nur Erwähnungen, Aus.
    func setMode(_ mode: ChannelMode, roomID: String) {
        guard let session else { return }
        roomModes[roomID] = mode
        Task {
            let settings = await session.client.getNotificationSettings()
            let sdkMode: RoomNotificationMode = switch mode {
            case .all: .allMessages
            case .mentions: .mentionsAndKeywordsOnly
            case .mute: .mute
            }
            do {
                try await settings.setRoomNotificationMode(roomId: roomID, mode: sdkMode)
            } catch {
                log.error("room mode failed: \(error.localizedDescription, privacy: .public)")
                await load()
            }
        }
    }


    private func putArticleRule(blogRoomID: String, session: ChatSession) async throws {
        let rule: [String: Any] = [
            "conditions": [
                ["kind": "event_match", "key": "room_id", "pattern": blogRoomID],
                ["kind": "event_match", "key": "content.de\\.iphoneblog\\.article.title", "pattern": "*"],
            ],
            "actions": ["notify", ["set_tweak": "sound", "value": "default"]],
        ]
        _ = try await session.api("PUT", "/_matrix/client/v3/pushrules/global/override/\(Self.articleRuleID)",
                                  body: JSONSerialization.data(withJSONObject: rule))
    }
}
