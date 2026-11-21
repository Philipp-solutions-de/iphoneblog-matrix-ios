import Foundation

/// Where the app is: the tab, the open channel, the open thread, the sign-in sheet.
/// One per app, signed in or not; the signed-in session borrows it.
@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case blog, chat, forYou, me }

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

    /// One step in the #one tab, on top of the hub (variant A, Thorsten 2026-11-18).
    enum ChatRoute: Hashable {
        /// The #one chat: the room bar and the open room (`currentRoomID`).
        case chat
        /// All episodes, newest first.
        case videos
        /// One episode's page with its player.
        case episode(Episode)
        case room(String)
        case thread(ThreadRoute)
        /// The threads you take part in, across the #one rooms.
        case threads
        /// Search in these rooms: one room from its header, all from the list's.
        /// Search in these rooms; `current` is the open room, for the "this room" chip.
        case search([String], current: String?)
        /// A video passage from the search: the episode's page, playing from `seconds`.
        /// `page` is the article with `?t=`, for an episode the list does not hold.
        case video(postID: Int, seconds: Int, page: URL?)
    }

    @Published var tab: Tab = Router.startTab {
        didSet { if !visitedTabs.contains(tab) { visitedTabs.insert(tab) } }
    }
    /// The tabs shown so far: a tab's screens are built when it is first shown, not at launch
    /// (MainView, 2026-11-21, docs/performance.md).
    @Published private(set) var visitedTabs: Set<Tab> = [Router.startTab]
    /// #one: the hub at the root; Chat (the room bar and the open room), Videos or an episode
    /// pushed on it; in Chat a thread, the Threads list or a search on top. `.room` routes are
    /// not pushed any more; the room bar switches rooms.
    @Published var chatPath: [ChatRoute] = []
    /// The room open in #one, remembered across launches: the tab opens the last room read.
    @Published var currentRoomID: String? = UserDefaults.standard.string(forKey: Router.lastRoomKey) {
        didSet {
            if let currentRoomID { UserDefaults.standard.set(currentRoomID, forKey: Router.lastRoomKey) }
            else { UserDefaults.standard.removeObject(forKey: Router.lastRoomKey) }
        }
    }
    private static let lastRoomKey = "one.lastRoom"
    /// The room on screen in #one, if any.
    var selectedRoomID: String? { currentRoomID }
    /// Blog: the open discussion on top of the blog.
    @Published var blogPath: [DiscussionRoute] = []
    /// The Blog room's ID once known, so a push or a link into it opens the Blog tab.
    var blogRoomID: String?

    @Published var presentedURL: URL?
    /// The search over blog and #one (SiteSearchView), a sheet over either tab.
    @Published var showSiteSearch = false
    /// A blog page for the Blog tab's web view to load (a search hit); BlogTab loads it and
    /// clears it.
    @Published var blogPageRequest: URL?
    /// A person's profile sheet; `shareNow` opens "Kontaktdaten teilen" in it at once.
    struct Person: Identifiable, Hashable {
        let userID: String
        let shareNow: Bool
        var id: String { userID }
    }
    @Published var profile: Person?
    /// A report from the conversation views (App/Sources/Moderation).
    @Published var moderation: ModerationRequest?
    @Published var notice: String?
    /// The sign-in sheet, offered where reading ends and writing would start.
    @Published var showSignIn = false
    /// The tab badges: #one-Chat's unread messages and unread @Mentions. ChatSession keeps them
    /// current; MainView observes only the router, so they live here.
    @Published var chatBadge = 0
    @Published var forYouBadge = 0
    /// A #one member: only members see #one-Chat and @Mentions (Thorsten, 2026-11-16). Set by
    /// ChatSession whenever membership changes, so the tabs follow without a restart.
    @Published var isMember = false {
        didSet {
            if !isMember, tab == .forYou || tab == .me { tab = .chat }
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
        if let user = env["IPHONEBLOG_START_PROFILE"], !user.isEmpty {
            profile = Person(userID: user, shareNow: env["IPHONEBLOG_START_SHARE"] == "1")
        }
        if let room = env["IPHONEBLOG_START_ROOM"], !room.isEmpty {
            currentRoomID = room
        }
        // Runs that start in #one land in Chat, as before the hub; IPHONEBLOG_START_HUB=1 stays
        // on the hub.
        if env["IPHONEBLOG_START_TAB"] == "chat", env["IPHONEBLOG_START_HUB"] != "1" {
            chatPath = [.chat]
        }
        if let value = env["IPHONEBLOG_START_THREAD"], case let parts = value.split(separator: "|"), parts.count == 2 {
            currentRoomID = String(parts[0])
            chatPath = [.chat, .thread(ThreadRoute(roomID: String(parts[0]), rootEventID: String(parts[1])))]
        }
        #endif
    }

    /// Blog, except in debug screenshot runs (IPHONEBLOG_START_TAB=blog|chat|foryou|me).
    private static var startTab: Tab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["IPHONEBLOG_START_TAB"] {
        case "chat": return .chat
        case "mentions", "foryou": return .forYou
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
        currentRoomID = roomID
        chatPath = [.chat]
    }

    /// Chat from the hub: the tile, "Alle", or a row of "Gerade aktiv" (that room).
    func openChat(roomID: String? = nil) {
        if let roomID { currentRoomID = roomID }
        tab = .chat
        chatPath = [.chat]
    }

    func openThreadsList() { chatPath.append(.threads) }

    /// Where a mention was said, from @Mentions and "Für dich" alike: a thread reply opens its
    /// thread, an article's discussion the Blog tab, a room message the room scrolled to it.
    func open(_ mention: MentionsModel.Mention) {
        switch mention.place {
        case .channel(let roomID, let root?, _):
            openThread(roomID: roomID, rootEventID: root)
        case .channel(let roomID, nil, _), .room(let roomID, _):
            openMessage(roomID: roomID, eventID: mention.id)
        case .discussion(let root, _):
            tab = .blog
            blogPath = [.thread(rootEventID: root)]
        }
    }

    /// The timeline the reader sees: the top of the visible tab's stack. Only it sends read
    /// receipts ("read up to here" must not reach messages nobody had on screen).
    func isOnScreen(roomID: String, threadRootEventID: String?) -> Bool {
        if presentedURL != nil || profile != nil || moderation != nil || showSignIn { return false }
        switch tab {
        case .chat:
            switch chatPath.last {
            case .chat?: return threadRootEventID == nil && currentRoomID == roomID
            case .room(let id)?: return threadRootEventID == nil && id == roomID
            case .thread(let thread)?: return thread.roomID == roomID && thread.rootEventID == threadRootEventID
            default: return false
            }
        case .blog:
            if case .thread(let root)? = blogPath.last { return roomID == blogRoomID && root == threadRootEventID }
            return false
        default:
            return false
        }
    }

    func openSearch(in roomIDs: [String], current: String? = nil) { chatPath.append(.search(roomIDs, current: current)) }

    /// A search result: the message in its channel, scrolled to and highlighted.
    func openMessage(roomID: String, eventID: String) {
        openRoom(roomID)
        ChatScreens.provider.focus(roomID: roomID, eventID: eventID)
    }

    /// A thread was opened on one of its replies: the route takes the real root, so the timeline
    /// and its receipts name the thread the server knows (ResolvedThreadScreen).
    func correctThread(roomID: String, from wrong: String, to root: String) {
        chatPath = chatPath.map { route in
            if case .thread(let thread) = route, thread.roomID == roomID, thread.rootEventID == wrong {
                return .thread(ThreadRoute(roomID: roomID, rootEventID: root))
            }
            return route
        }
    }

    func openThread(roomID: String, rootEventID: String) {
        if roomID == blogRoomID {
            tab = .blog
            blogPath = [.thread(rootEventID: rootEventID)]
            return
        }
        tab = .chat
        let thread = ChatRoute.thread(ThreadRoute(roomID: roomID, rootEventID: rootEventID))
        // From the Threads list or a search, the thread goes on top, so back returns there.
        if case .threads? = chatPath.last { chatPath.append(thread); return }
        if case .search? = chatPath.last { chatPath.append(thread); return }
        // Otherwise over its room, so back leads into the room.
        currentRoomID = roomID
        chatPath = [.chat, thread]
    }

    /// Where a search hit opens (ADR-0010): a post in the Blog tab's web view, a video in its
    /// episode page at the passage, a chat message in its room or thread, a discussion reply in
    /// the article's discussion, a link in Safari. Pure, so it is tested without screens.
    enum SearchTarget: Equatable {
        case blogPage(URL)
        case video(postID: Int, seconds: Int, page: URL?)
        case message(roomID: String, eventID: String)
        case thread(roomID: String, rootEventID: String)
        case discussion(rootEventID: String)
        case outside(URL)
        case nothing
    }

    /// `chat`: the reader is a #one member with a session, so the #one tab can show rooms and
    /// episodes.
    static func target(for hit: SiteSearchHit, chat: Bool) -> SearchTarget {
        switch hit.kind {
        case .post, .one:
            return hit.url.map(SearchTarget.blogPage) ?? .nothing
        case .video:
            let page = hit.deepLink ?? hit.url
            if chat, let postID = hit.postID { return .video(postID: postID, seconds: hit.seconds ?? 0, page: page) }
            return page.map(SearchTarget.blogPage) ?? .nothing
        case .chat:
            guard chat, let roomID = hit.roomID, let eventID = hit.eventID else {
                return hit.deepLink.map(SearchTarget.outside) ?? .nothing
            }
            if let root = hit.threadRoot, root != eventID { return .thread(roomID: roomID, rootEventID: root) }
            return .message(roomID: roomID, eventID: eventID)
        case .discussion:
            // The reply's thread is the article's discussion, readable signed out too.
            if let root = hit.threadRoot ?? hit.eventID { return .discussion(rootEventID: root) }
            return hit.url.map(SearchTarget.blogPage) ?? .nothing
        case .link:
            return (hit.deepLink ?? hit.url).map(SearchTarget.outside) ?? .nothing
        }
    }

    /// Opens a search hit's target; `.outside` is the caller's (Safari).
    func open(_ target: SearchTarget) {
        switch target {
        case .blogPage(let url):
            tab = .blog
            blogPath = []
            blogPageRequest = url
        case .video(let postID, let seconds, let page):
            tab = .chat
            chatPath = [.video(postID: postID, seconds: seconds, page: page)]
        case .message(let roomID, let eventID):
            openMessage(roomID: roomID, eventID: eventID)
        case .thread(let roomID, let root):
            openThread(roomID: roomID, rootEventID: root)
        case .discussion(let root):
            tab = .blog
            blogPath = [.thread(rootEventID: root)]
        case .outside, .nothing:
            break
        }
    }

    /// Back to a clean state after signing out; the Blog tab stays readable.
    func reset() {
        showSiteSearch = false
        currentRoomID = nil
        tab = .blog
        chatPath = []
        blogPath = []
        blogRoomID = nil
        chatBadge = 0
        forYouBadge = 0
        isMember = false
        moderation = nil
        profile = nil
    }
}
