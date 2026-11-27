import Foundation
import MatrixRustSDK

/// Posts a share into a room, from the share extension (and the integration test, which runs it
/// beside a signed-in app as the extension runs beside the app on a phone).
///
/// It opens the app's Matrix store in the app group with the shared session, as the
/// notification extension does, loads only the chosen room and posts with `sendRaw`: that waits
/// for the server's answer, so the sheet closes only once the message is in the room (the SDK's
/// send queue would still be sending when iOS ends the extension). Pictures go up with
/// `uploadMedia` first. The SDK refreshes the token under the store's cross-process lock.
struct ShareSender {
    /// One picture, ready to upload (SharedImage in the extension).
    struct Picture {
        var data: Data
        var mimeType: String
        var fileName: String
        var width: Int
        var height: Int
    }

    var store = SessionStore()
    var process = "share-extension"

    /// Sends the words (with the link) as one text message, or each picture with the words as
    /// the first one's caption. Returns the new events' IDs.
    @discardableResult
    func send(roomID: String, text: String?, pictures: [Picture]) async throws -> [String] {
        guard let stored = store.load() else { throw ShareError.signedOut }
        let client = try await MatrixClientFactory.makeClient(homeserverURL: stored.homeserverURL,
                                                              storeID: stored.storeID,
                                                              sessionDelegate: KeychainSessionDelegate(store: store, storeID: stored.storeID),
                                                              process: process)
        try await client.restoreSessionWith(session: stored.sdkSession, roomLoadSettings: .one(roomId: roomID))
        guard let room = try client.getRoom(roomId: roomID) else { throw ShareError.noRoom }
        var events: [String] = []
        if pictures.isEmpty {
            guard let text else { return [] }
            events.append(try await room.sendRaw(eventType: "m.room.message", content: ShareMessage.textContent(text)))
        }
        for (index, picture) in pictures.enumerated() {
            let url = try await client.uploadMedia(mimeType: picture.mimeType, data: picture.data, progressWatcher: nil)
            let image = ShareMessage.Image(url: url, mimeType: picture.mimeType, fileName: picture.fileName,
                                           size: picture.data.count, width: picture.width, height: picture.height)
            events.append(try await room.sendRaw(eventType: "m.room.message",
                                                 content: ShareMessage.imageContent(image, caption: index == 0 ? text : nil)))
        }
        return events
    }
}

enum ShareError: Error {
    case signedOut
    case noRoom
}
