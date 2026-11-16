import Combine
import Foundation
import MatrixRustSDK
import OSLog

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
        let unread: Bool
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

    /// "Alle als gelesen": every room with an unread mention gets a read receipt up to its
    /// newest message, so the mentions, the badges and the rooms' counts clear.
    func markAllRead() async {
        guard let session else { return }
        for roomID in Set(items.filter(\.unread).map(\.roomID)) {
            try? await session.client.getRoom(roomId: roomID)?.markAsRead(receiptType: .read)
        }
        reload()
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
        guard event.sender != session.userID, let body = event.content?.body else { return nil }
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
                       unread: !entry.read)
    }

    /// An article's title by its thread root, fetched once per app run.
    private var titles: [String: String] = [:]
    private func threadTitle(_ root: String) async -> String? {
        if let known = titles[root] { return known }
        guard let title = try? await DiscussionStore.shared.thread(root).root.title else { return nil }
        titles[root] = title
        return title
    }

    private func name(of userID: String, session: ChatSession) async -> String {
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
            let relatesTo: Relation?

            enum CodingKeys: String, CodingKey { case body, relatesTo = "m.relates_to" }
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
        case all = "Alle Nachrichten"
        case mentions = "Nur @Mentions"
        case mute = "Stumm"
        var id: String { rawValue }
    }

    @Published private(set) var newArticles = true
    @Published private(set) var mentions = true
    @Published private(set) var channel: ChannelMode = .all
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
        newArticles = (try? await session.api("GET", "/_matrix/client/v3/pushrules/global/override/\(Self.articleRuleID)")) != nil
        mentions = (try? await settings.isUserMentionEnabled()) ?? true
        if let channelID = session.oneChannelID,
           let current = try? await settings.getRoomNotificationSettings(roomId: channelID, isEncrypted: false, isOneToOne: false) {
            channel = switch current.mode {
            case .allMessages: .all
            case .mentionsAndKeywordsOnly: .mentions
            case .mute: .mute
            }
        }
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

    func setChannel(_ mode: ChannelMode) {
        // One switch for the whole #one-Chat area: every #one room gets the mode.
        guard let session, !session.rooms.channelIDs.isEmpty else { return }
        let channelIDs = session.rooms.channelIDs
        channel = mode
        Task {
            let settings = await session.client.getNotificationSettings()
            let sdkMode: RoomNotificationMode = switch mode {
            case .all: .allMessages
            case .mentions: .mentionsAndKeywordsOnly
            case .mute: .mute
            }
            do {
                for channelID in channelIDs {
                    try await settings.setRoomNotificationMode(roomId: channelID, mode: sdkMode)
                }
            } catch {
                log.error("channel mode failed: \(error.localizedDescription, privacy: .public)")
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
