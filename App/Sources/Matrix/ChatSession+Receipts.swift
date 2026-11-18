import Foundation
import MatrixRustSDK
import OSLog

/// **The unthreaded receipt.** The timelines send only threaded receipts ("main" and one per
/// thread). The Rust SDK counts a room's unread messages from the newest of the account's main
/// and unthreaded receipts, and thread replies after the main receipt keep that count up: Alex's
/// #entertainment showed 1 while the server had 0. When the room's own timeline has been read up
/// to its newest message, an unthreaded receipt goes to the room's newest event.
///
/// **Hidden events count too.** A room push rule set to "notify" matches every event in the room,
/// a reaction's redaction included, and the server counts it as a notification that no timeline
/// ever shows, so no receipt reaches it: Philip's #bugs kept 1 on the server, and with it the app
/// icon's badge (2026-11-18). So the receipt goes on the newest event when everything after the
/// message read is hidden: redactions, reactions, edits, state.
///
/// An unthreaded receipt also covers every thread reply before it, and @Mentions counts those as
/// read. So it is held back while a thread mention in that room is still unread, and it never
/// passes a message the reader has not seen, a thread reply included.
extension ChatSession {
    func catchUpUnthreadedReceipt(roomID: String, eventID: String, isPrivate: Bool) async {
        let log = Logger(subsystem: Brand.bundleID, category: "receipts")
        let waiting = mentions.items.filter { $0.roomID == roomID && $0.threadRoot != nil && $0.unread }.count
        guard waiting == 0 else {
            log.info("no unthreaded receipt: \(waiting, privacy: .public) unread thread mentions")
            return
        }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let room = try? client.getRoom(roomId: roomID),
              let path = roomID.addingPercentEncoding(withAllowedCharacters: allowed),
              let data = try? await api("GET", "/_matrix/client/v3/rooms/\(path)/messages?dir=b&limit=30"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chunk = json["chunk"] as? [[String: Any]] else { return }
        let events = chunk.map(UnthreadedReceipt.Event.init)
        guard let target = UnthreadedReceipt.target(read: eventID, newestFirst: events) else {
            log.info("no unthreaded receipt: an unread message comes after the one read")
            return
        }
        let type: ReceiptType = isPrivate ? .readPrivate : .read
        do {
            try await room.sendSingleReceipt(receiptType: type, thread: .unthreaded, eventId: target)
        } catch {
            log.error("unthreaded receipt failed: \(error.localizedDescription, privacy: .public)")
        }
        // Synapse counts each thread from its own receipt, "main" from the main one: the
        // unthreaded receipt alone left Philip's count at the redaction. The main receipt
        // follows to the newest hidden event the server files under "main".
        if let main = UnthreadedReceipt.mainTarget(read: eventID, newestFirst: events), main != eventID {
            do {
                try await room.sendSingleReceipt(receiptType: type, thread: .main, eventId: main)
            } catch {
                log.error("main receipt failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// The rule for the unthreaded receipt, apart so a unit test can hold it.
enum UnthreadedReceipt {
    struct Event: Equatable {
        let id: String
        /// Shown as its own row somewhere: a message in the room or in a thread, a poll, a sticker.
        let isVisible: Bool
        /// Where the server files it, as far as the event shows: "main" for a room message, a
        /// redaction (it carries no relation) or a state event; a root for a thread reply; nil
        /// for a reaction or edit, which goes with the event it relates to (`relatesTo`).
        let thread: String?
        let relatesTo: String?

        init(id: String, isVisible: Bool, thread: String? = "main", relatesTo: String? = nil) {
            self.id = id
            self.isVisible = isVisible
            self.thread = thread
            self.relatesTo = relatesTo
        }

        init(_ json: [String: Any]) {
            id = json["event_id"] as? String ?? ""
            let type = json["type"] as? String ?? ""
            let relation = (json["content"] as? [String: Any])?["m.relates_to"] as? [String: Any]
            let kind = relation?["rel_type"] as? String
            let hidden = json["state_key"] != nil
                || type == "m.room.redaction" || type == "m.reaction"
                || kind == "m.replace" || kind == "m.annotation"
            isVisible = !hidden
            switch kind {
            case "m.thread":
                thread = relation?["event_id"] as? String
                relatesTo = nil
            case "m.annotation", "m.replace":
                thread = nil
                relatesTo = relation?["event_id"] as? String
            default:
                // A redaction of a redacted reaction keeps no relation either; the server files
                // a redaction under "main".
                thread = type == "m.reaction" ? nil : "main"
                relatesTo = nil
            }
        }
    }

    /// The newest hidden event after the message read that the server files under "main", for
    /// the main receipt; the message read itself when there is none. nil when an unseen message
    /// is newer. A reaction or edit counts only when the event it relates to is a room message
    /// in sight; one on a thread reply belongs to that thread, and a main receipt on it is a 400.
    static func mainTarget(read: String, newestFirst: [Event]) -> String? {
        guard target(read: read, newestFirst: newestFirst) != nil else { return nil }
        let byID = Dictionary(newestFirst.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for event in newestFirst {
            if event.id == read { return read }
            if event.thread == "main" { return event.id }
            if event.thread == nil, let parent = event.relatesTo, byID[parent]?.thread == "main" { return event.id }
        }
        return read
    }

    /// The event the unthreaded receipt goes on, given the one the reader's room timeline read
    /// up to and the room's newest events, newest first: the newest event, when nothing between
    /// it and the one read is a visible message; nil when an unseen message is newer, or the
    /// one read is not among them.
    static func target(read: String, newestFirst: [Event]) -> String? {
        guard let newest = newestFirst.first else { return nil }
        for event in newestFirst {
            if event.id == read { return newest.id }
            if event.isVisible { return nil }
        }
        return nil
    }
}
