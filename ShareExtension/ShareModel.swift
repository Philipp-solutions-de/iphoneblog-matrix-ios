import Foundation
import UIKit
import UniformTypeIdentifiers

/// The share sheet's state: what was shared, the rooms on offer, and the send (ShareSender).
@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// No session in the keychain: the member signs in in the app first.
        case signedOut
        /// Signed in, but no #one room to write in (not a member, or the app not opened since).
        case noRooms
        case ready
        case sending
    }

    @Published private(set) var state: State = .loading
    @Published var words = ""
    @Published private(set) var link: URL?
    @Published private(set) var linkTitle: String?
    @Published private(set) var images: [SharedImage] = []
    @Published private(set) var rooms: [ShareTargets.Room] = []
    @Published var roomID: String?
    @Published var failure: String?
    /// Pictures that could not be read (a format ImageIO does not know).
    @Published private(set) var skipped = 0

    var finish: (Bool) -> Void = { _ in }

    private let items: [NSExtensionItem]
    private let sessionStore = SessionStore()

    init(items: [NSExtensionItem]) {
        self.items = items
    }

    var canSend: Bool {
        state == .ready && roomID != nil && (!images.isEmpty || ShareMessage.text(words: words, link: link) != nil)
    }

    func load() async {
        guard let session = sessionStore.load() else {
            state = .signedOut
            return
        }
        let targets = ShareTargets.load(for: session.userID)?.rooms ?? []
        rooms = targets
        roomID = ShareTargets(userID: session.userID, rooms: targets).preselected(last: ShareTargets.lastRoomID())?.id
        await readItems()
        state = targets.isEmpty ? .noRooms : .ready
    }

    private func readItems() async {
        var texts: [String] = []
        for item in items {
            if linkTitle == nil, let title = item.attributedTitle?.string, !title.isEmpty { linkTitle = title }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let image = await SharedImage.load(from: provider) { images.append(image) } else { skipped += 1 }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if link == nil, let url = await Self.loadURL(provider) { link = url }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await Self.loadText(provider) {
                        if link == nil, let url = ShareMessage.link(inText: text) { link = url } else { texts.append(text) }
                    }
                }
            }
            // Some apps put their words beside the link in the item itself.
            if texts.isEmpty, let text = item.attributedContentText?.string,
               !text.isEmpty, text != linkTitle, text != link?.absoluteString {
                texts.append(text)
            }
        }
        words = texts.joined(separator: "\n\n")
    }

    func send() async {
        guard canSend, let roomID else { return }
        state = .sending
        failure = nil
        do {
            let pictures = images.map { ShareSender.Picture(data: $0.data, mimeType: $0.mimeType, fileName: $0.fileName,
                                                            width: $0.width, height: $0.height) }
            try await ShareSender(store: sessionStore).send(roomID: roomID, text: ShareMessage.text(words: words, link: link),
                                                            pictures: pictures)
            ShareTargets.remember(roomID: roomID)
            finish(true)
        } catch {
            state = .ready
            failure = Self.describe(error)
        }
    }

    func cancel() { finish(false) }

    private static func describe(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("M_FORBIDDEN") { return "In diesem Raum darfst du nicht schreiben." }
        if case ShareError.signedOut = error { return "Du bist nicht mehr angemeldet. Öffne die App und melde dich an." }
        if case ShareError.noRoom = error { return "Diesen Raum kennt die App nicht mehr. Öffne die App einmal und versuche es dann wieder." }
        if text.contains("M_UNKNOWN_TOKEN") { return "Deine Anmeldung ist abgelaufen. Öffne die App und melde dich wieder an." }
        return "Das ging nicht raus. Prüfe die Verbindung und versuche es noch einmal."
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
        return ShareMessage.webLink((item as? URL) ?? (item as? String).flatMap(URL.init(string:)))
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        if let text = item as? String { return text }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }
}

