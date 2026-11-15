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

    @Published var tab: Tab = Router.startTab
    /// #one-Chat: the open channel and the thread on top of it.
    @Published var selectedRoomID: String?
    @Published var threadPath: [ThreadRoute] = []
    /// A thread to open once its channel's screen exists (set from another tab or a push).
    @Published var pendingThread: ThreadRoute?
    /// Blog: the open article thread, by its root event.
    @Published var blogPath: [String] = []
    /// The Blog room's ID once known, so a push or a link into it opens the Blog tab.
    var blogRoomID: String?

    @Published var presentedURL: URL?
    @Published var notice: String?
    /// The sign-in sheet, offered where reading ends and writing would start.
    @Published var showSignIn = false

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
        threadPath = []
        selectedRoomID = roomID
    }

    func openThread(roomID: String, rootEventID: String) {
        if roomID == blogRoomID {
            tab = .blog
            blogPath = [rootEventID]
            return
        }
        let route = ThreadRoute(roomID: roomID, rootEventID: rootEventID)
        if tab == .chat, selectedRoomID == roomID {
            threadPath = [route]
        } else {
            // Switching tab or channel rebuilds the channel's navigation stack, which would drop a
            // path set now. ChatsView opens the pending thread once the stack is on screen.
            pendingThread = route
            openRoom(roomID)
        }
    }

    /// Back to a clean state after signing out; the Blog tab stays readable.
    func reset() {
        tab = .blog
        selectedRoomID = nil
        threadPath = []
        pendingThread = nil
        blogPath = []
        blogRoomID = nil
    }
}
