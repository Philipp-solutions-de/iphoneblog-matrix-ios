import OSLog
import SwiftUI

/// A thread, opened only on its real root.
///
/// A link, a push or a list can carry the ID of a reply in the thread instead of its root. A
/// thread timeline built on a reply sends its read receipts with that reply as `thread_id`, and
/// Synapse refuses each one with 400 "is not related to thread" (Alex's build, 2026-11-17, nine
/// times in #bugs; ReceiptsUITests). So the route's ID is checked against the server first: an
/// event with an m.thread relation is a reply, and the route moves to its root.
struct ResolvedThreadScreen: View {
    let thread: Router.ThreadRoute
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @State private var checked: String?

    var body: some View {
        Group {
            if checked == thread.rootEventID {
                ChatScreens.provider.threadScreen(roomID: thread.roomID, rootEventID: thread.rootEventID, host: session)
            } else {
                ProgressView()
            }
        }
        .task(id: thread) {
            // Right after launch the session may not answer yet: ask again for up to 30 s, then
            // open the thread as it came rather than not at all.
            let log = Logger(subsystem: Brand.bundleID, category: "receipts")
            for attempt in 0..<30 {
                let relation = await session.threadRelation(of: thread.rootEventID, in: thread.roomID)
                log.info("thread check \(attempt, privacy: .public): \(String(describing: relation), privacy: .public)")
                switch relation {
                case .some(.some(let root)) where root != thread.rootEventID:
                    router.correctThread(roomID: thread.roomID, from: thread.rootEventID, to: root)
                    return
                case .some:
                    checked = thread.rootEventID
                    return
                case nil:
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
            }
            checked = thread.rootEventID
        }
    }
}
