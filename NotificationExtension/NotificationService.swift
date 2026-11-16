import MatrixRustSDK
import UserNotifications

/// Turns Sygnal's bare push (event id and room id) into "Name in #channel: text".
/// It opens the app's Matrix store from the shared app group with the shared session and
/// asks the SDK's notification client for the event. No encryption: nothing to decrypt.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var task: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        content.title = Brand.appName
        content.body = "Neue Nachricht"
        content.sound = .default
        bestAttempt = content

        let userInfo = request.content.userInfo
        guard let roomID = userInfo["room_id"] as? String,
              let eventID = userInfo["event_id"] as? String else {
            return deliver()
        }
        content.threadIdentifier = roomID

        task = Task {
            await fill(content, roomID: roomID, eventID: eventID)
            deliver()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        task?.cancel()
        deliver()
    }

    private func deliver() {
        guard let handler = contentHandler, let content = bestAttempt else { return }
        contentHandler = nil
        handler(content)
    }

    private func fill(_ content: UNMutableNotificationContent, roomID: String, eventID: String) async {
        let store = SessionStore()
        guard let stored = store.load() else { return }
        do {
            let client = try await MatrixClientFactory.makeClient(homeserverURL: stored.homeserverURL,
                                                                  storeID: stored.storeID,
                                                                  sessionDelegate: KeychainSessionDelegate(store: store, storeID: stored.storeID),
                                                                  process: "notification-extension")
            try await client.restoreSessionWith(session: stored.sdkSession, roomLoadSettings: .one(roomId: roomID))
            let notifications = try await client.notificationClient(processSetup: .multipleProcesses)
            guard case .event(let item) = try await notifications.getNotification(roomId: roomID, eventId: eventID) else { return }
            Self.apply(item, to: content)
        } catch {
            // Keep the plain "Neue Nachricht": better than no push.
        }
    }

    static func apply(_ item: NotificationItem, to content: UNMutableNotificationContent) {
        let sender = item.senderInfo.displayName ?? "Jemand"
        let room = item.roomInfo.displayName
        if item.roomInfo.isDirect {
            content.title = sender
        } else {
            // One "#" ("#one-Chat" carries its own), and "· Thread" for a thread reply (PushText).
            content.title = PushText.title(room: room, inThread: item.threadId != nil)
            content.subtitle = sender
        }
        if let threadID = item.threadId {
            content.userInfo["thread_root"] = threadID
            content.threadIdentifier = threadID
        }
        guard case .timeline(let event) = item.event,
              case .messageLike(let messageLike) = try? event.content(),
              case .roomMessage(let type, _) = messageLike else { return }
        content.body = Self.text(of: type)
    }

    static func text(of type: MessageType) -> String {
        switch type {
        // Plain text on the lock screen: no markdown, links or HTML (PushText).
        case .text(let c): PushText.plain(body: c.body, formattedBody: html(c.formatted))
        case .notice(let c): PushText.plain(body: c.body, formattedBody: html(c.formatted))
        case .emote(let c): "* " + PushText.plain(body: c.body, formattedBody: html(c.formatted))
        case .image(let c): c.caption ?? "Bild"
        case .video: "Video"
        case .audio: "Audio"
        case .file(let c): c.filename
        case .gallery: "Bilder"
        case .location: "Standort"
        case .other(_, let body): body
        }
    }

    private static func html(_ formatted: FormattedBody?) -> String? {
        guard let formatted, case .html = formatted.format else { return nil }
        return formatted.body
    }
}
