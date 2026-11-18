import Foundation
import MatrixRustSDK
import OSLog

/// **The unthreaded receipt.** The timelines send only threaded receipts ("main" and one per
/// thread). The Rust SDK counts a room's unread messages from the newest of the account's main
/// and unthreaded receipts, and thread replies after the main receipt keep that count up: Alex's
/// #entertainment showed 1 while the server had 0. When the room's own timeline has been read up
/// to the room's newest event, an unthreaded receipt goes to the same event.
///
/// An unthreaded receipt also covers every thread reply before it, and @Mentions counts those as
/// read. So it is held back while a thread mention in that room is still unread.
extension ChatSession {
    func catchUpUnthreadedReceipt(roomID: String, eventID: String, isPrivate: Bool) async {
        guard let room = try? client.getRoom(roomId: roomID) else { return }
        let latest: Date? = switch await room.latestEvent() {
        case .remote(let timestamp, _, _, _, _): Date(timeIntervalSince1970: Double(timestamp) / 1000)
        case .local(let timestamp, _, _, _, _): Date(timeIntervalSince1970: Double(timestamp) / 1000)
        default: nil
        }
        let viewed = await mentions.eventTime(eventID, roomID: roomID, session: self)
        let waiting = mentions.items.filter { $0.roomID == roomID && $0.threadRoot != nil && $0.unread }.count
        guard UnthreadedReceipt.shouldSend(viewed: viewed, latest: latest, unreadThreadMentions: waiting) else {
            Logger(subsystem: Brand.bundleID, category: "receipts")
                .info("no unthreaded receipt: viewed \(viewed?.timeIntervalSince1970 ?? -1, privacy: .public), latest \(latest?.timeIntervalSince1970 ?? -1, privacy: .public), unread thread mentions \(waiting, privacy: .public)")
            return
        }
        do {
            try await room.sendSingleReceipt(receiptType: isPrivate ? .readPrivate : .read, thread: .unthreaded, eventId: eventID)
        } catch {
            Logger(subsystem: Brand.bundleID, category: "receipts")
                .error("unthreaded receipt failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The rule for the unthreaded receipt, apart so a unit test can hold it.
enum UnthreadedReceipt {
    /// Only for the room's newest event (or one at least as new: the list can lag), and never
    /// while a thread mention in the room is unread. Unknown times send nothing.
    static func shouldSend(viewed: Date?, latest: Date?, unreadThreadMentions: Int) -> Bool {
        guard let viewed, let latest, unreadThreadMentions == 0 else { return false }
        return viewed >= latest
    }
}
