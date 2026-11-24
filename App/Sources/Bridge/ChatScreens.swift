//
// The contract between our app shell (App/) and the conversation views (Vendor/).
//
// The app owns this file. Vendor/ElementX implements `ChatScreenProviding`; the app only ever
// talks to the views through it, so the views can be re-synced from Element X or swapped for
// another kit (exyte/Chat) without touching the shell. docs/architecture.md, "Kept apart".
//

import Combine
import MatrixRustSDK
import SwiftUI

/// A thread you take part in, for "Für dich".
struct InvolvedThread: Identifiable, Equatable {
    var id: String { roomID + "|" + rootEventID }
    let roomID: String
    let roomName: String
    let rootEventID: String
    let rootText: String
    let rootSenderID: String
    let rootSenderName: String?
    let replies: Int
    let latestSenderID: String?
    let latestSenderName: String?
    let latestText: String?
    let lastActivity: Date
    /// New replies since you last had it open on this device.
    let isUnread: Bool
}

/// What the app gives the conversation views: the signed-in account and a way back into the
/// app's navigation. Implemented by the app (`ChatSession`).
@MainActor
protocol ChatHost: AnyObject {
    /// The signed-in Matrix client. Sync runs in the app; the views read and send through it.
    var client: Client { get }
    /// `@name:iphoneblog.de` of the signed-in person.
    var userID: String { get }
    /// The room list service of the running sync, for `room(roomId:)` with live room info.
    var roomListService: RoomListService { get }

    /// Opens a thread of this room as its own screen (iPhone) or column (iPad).
    func openThread(roomID: String, rootEventID: String)
    /// Opens a person's profile sheet, with "Kontaktdaten teilen".
    func openUser(userID: String)
    /// Opens "Kontaktdaten teilen" with this person straight away (a long press on the name).
    func shareContact(userID: String)
    /// Opens a room by ID, for example a room link inside a message.
    func openRoom(roomID: String)
    /// Opens a web address the way the app wants (in-app Safari).
    func openURL(_ url: URL)
    /// Shows a short notice (sent, copied, failed) the app's way.
    func showMessage(_ text: String)
    /// Asks why, then reports the message to the moderators (App/Sources/Moderation).
    func reportMessage(roomID: String, eventID: String)
    /// Whether a room's composer offers "GIFs aus dem Chat" (#one rooms only, not the Blog room).
    func offersGIFs(roomID: String) -> Bool
    /// Shows "GIFs aus dem Chat"; `send` gets the picked GIF's mxc, width, height and size, and
    /// the views send it into the room or thread the composer belongs to (App/Sources/GIFs).
    func pickGIF(roomID: String, send: @escaping @MainActor (_ mxc: String, _ width: Int?, _ height: Int?, _ size: Int?) -> Void)
    /// Whether a GIF of one's own (by its file's SHA-256) needs tags for the library.
    func gifNeedsTags(sha256: String) async -> Bool
    /// Adds tags to a GIF after it was sent.
    func tagGIF(sha256: String, tags: [String]) async
    /// "jubeln, facepalm" as tags, or why not, by the server's rules.
    func parseGIFTags(_ text: String) -> (tags: [String], problem: String?)
    /// A timeline showed the reader up to `eventID` (in a thread when `threadRootEventID` is set)
    /// and sent its read receipt, private when `isPrivate`.
    func didSee(roomID: String, threadRootEventID: String?, eventID: String, isPrivate: Bool)
    /// Whether this room's timeline (or this thread) is the screen on top right now.
    func isOnScreen(roomID: String, threadRootEventID: String?) -> Bool
}

/// What the conversation views give the app. Implemented once in Vendor/ (today Element X's
/// transplanted views); `PlaceholderChatScreens` stands in until that lands.
@MainActor
protocol ChatScreenProviding: AnyObject {
    /// Called once per signed-in account after sync started, before any screen is asked for.
    /// Set up per-account state here (Vendor/ElementX: its `ChatKitSession`, theme).
    func start(host: ChatHost) async throws
    /// A channel or direct message: timeline, composer, reactions, thread summaries.
    func roomScreen(roomID: String, host: ChatHost) -> AnyView
    /// One thread: root message, replies, composer that answers in the thread.
    func threadScreen(roomID: String, rootEventID: String, host: ChatHost) -> AnyView
    /// The Threads tab: every thread you take part in across channels, newest activity first,
    /// unread marked. A tap calls `host.openThread(roomID:rootEventID:)`.
    func threadsScreen(host: ChatHost) -> AnyView
    /// Scrolls a room's timeline to a message and highlights it (a search result).
    func focus(roomID: String, eventID: String)
    /// The "Threads" row at the top of #one-Chat, with the count of your threads that have news.
    func threadsEntry(host: ChatHost, open: @escaping () -> Void) -> AnyView
    /// The threads you take part in, newest activity first ("Für dich").
    func involvedThreads() -> AnyPublisher<[InvolvedThread], Never>
    /// These threads count as seen now (on this device).
    func markThreadsSeen(_ threads: [InvolvedThread])
    /// The accounts the chat server lists as bots, marked "Bot" in the conversation views.
    func setBots(_ ids: Set<String>)
    /// The room under the app's own header (the #one room bar): no title of its own.
    func roomScreenUnderBar(roomID: String, host: ChatHost) -> AnyView
    /// An article's thread under the app's own discussion header: the thread screen without
    /// its "Thread" title.
    func discussionScreen(roomID: String, rootEventID: String, host: ChatHost) -> AnyView
}

extension ChatScreenProviding {
    /// The room under the app's own header (the #one room bar): no title of its own.
    func roomScreenUnderBar(roomID: String, host: ChatHost) -> AnyView {
        roomScreen(roomID: roomID, host: host)
    }

    func discussionScreen(roomID: String, rootEventID: String, host: ChatHost) -> AnyView {
        threadScreen(roomID: roomID, rootEventID: rootEventID, host: host)
    }
}

/// The views the app uses. Vendor/ replaces the placeholder in one line here.
@MainActor
enum ChatScreens {
    static var provider: ChatScreenProviding = ElementXChatScreens()
}
