import Foundation

/// Where the app is: the tab, the open channel, the open thread, the sign-in sheet.
/// One per app, signed in or not; the signed-in session borrows it.
@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case blog, chat, mentions, me }

    struct ThreadRoute: Hashable {
        let roomID: String
        let rootEventID: String
    }

    /// A discussion under an article: from the blog's "Diskussion" link (by the article's URL)
    /// or from a push or a mention (by the thread's root event).
    enum DiscussionRoute: Hashable {
        case article(URL)
        case thread(rootEventID: String)
    }

    /// One step in the #one-Chat tab, on top of its list of rooms.
    enum ChatRoute: Hashable {
        case room(String)
        case thread(ThreadRoute)
        /// The threads you take part in, across the #one rooms.
        case threads
        /// Search in these rooms: one room from its header, all from the list's.
        case search([String])
    }

    @Published var tab: Tab = Router.startTab
    /// #one-Chat: the room list, then the open room, a thread, the Threads list or a search.
    @Published var chatPath: [ChatRoute] = []
    /// The room on screen in #one-Chat, if any.
    var selectedRoomID: String? {
        for step in chatPath.reversed() { if case .room(let id) = step { return id } }
        return nil
    }
    /// Blog: the open discussion on top of the blog.
    @Published var blogPath: [DiscussionRoute] = []
    /// The Blog room's ID once known, so a push or a link into it opens the Blog tab.
    var blogRoomID: String?

    @Published var presentedURL: URL?
    /// A person's profile sheet; `shareNow` opens "Kontaktdaten teilen" in it at once.
    struct Person: Identifiable, Hashable {
        let userID: String
        let shareNow: Bool
        var id: String { userID }
    }
    @Published var profile: Person?
    @Published var notice: String?
    /// The sign-in sheet, offered where reading ends and writing would start.
    @Published var showSignIn = false
    /// The tab badges: #one-Chat's unread messages and unread @Mentions. ChatSession keeps them
    /// current; MainView observes only the router, so they live here.
    @Published var chatBadge = 0
    @Published var mentionsBadge = 0
    /// A #one member: only members see #one-Chat and @Mentions (Thorsten, 2026-11-16). Set by
    /// ChatSession whenever membership changes, so the tabs follow without a restart.
    @Published var isMember = false {
        didSet {
            if !isMember, tab == .mentions || tab == .me { tab = .chat }
        }
    }

    /// Debug screenshot runs open a discussion (IPHONEBLOG_START_DISCUSSION=<root event>), a room
    /// (IPHONEBLOG_START_ROOM=<room>) or a thread (IPHONEBLOG_START_THREAD=<room>|<root event>).
    init() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let root = env["IPHONEBLOG_START_DISCUSSION"], !root.isEmpty {
            blogPath = [.thread(rootEventID: root)]
        }
        if let room = env["IPHONEBLOG_START_ROOM"], !room.isEmpty {
            chatPath = [.room(room)]
        }
        if let value = env["IPHONEBLOG_START_THREAD"], case let parts = value.split(separator: "|"), parts.count == 2 {
            chatPath = [.room(String(parts[0])), .thread(ThreadRoute(roomID: String(parts[0]), rootEventID: String(parts[1])))]
        }
        #endif
    }

    /// Blog, except in debug screenshot runs (IPHONEBLOG_START_TAB=blog|chat|mentions|me).
    private static var startTab: Tab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["IPHONEBLOG_START_TAB"] {
        case "chat": return .chat
        case "mentions": return .mentions
        case "me": return .me
        default: return .blog
        }
        #else
        return .blog
        #endif
    }

    func openRoom(_ roomID: String) {
        if roomID == blogRoomID {
            tab = .blog
            blogPath = []
            return
        }
        tab = .chat
        chatPath = [.room(roomID)]
    }

    func openThreadsList() { chatPath.append(.threads) }

    func openSearch(in roomIDs: [String]) { chatPath.append(.search(roomIDs)) }

    /// A search result: the message in its channel, scrolled to and highlighted.
    func openMessage(roomID: String, eventID: String) {
        openRoom(roomID)
        ChatScreens.provider.focus(roomID: roomID, eventID: eventID)
    }

    func openThread(roomID: String, rootEventID: String) {
        if roomID == blogRoomID {
            tab = .blog
            blogPath = [.thread(rootEventID: rootEventID)]
            return
        }
        // The thread over its room, so back leads into the room, then to the list.
        tab = .chat
        chatPath = [.room(roomID), .thread(ThreadRoute(roomID: roomID, rootEventID: rootEventID))]
    }

    /// Back to a clean state after signing out; the Blog tab stays readable.
    func reset() {
        tab = .blog
        chatPath = []
        blogPath = []
        blogRoomID = nil
        chatBadge = 0
        mentionsBadge = 0
        isMember = false
    }
}
