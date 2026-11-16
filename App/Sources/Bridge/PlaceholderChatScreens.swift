import MatrixRustSDK
import SwiftUI

/// Stands in for the conversation views until Vendor/ElementX lands: shows the room's name
/// and says what comes next, so `main` builds and runs at every step.
@MainActor
final class PlaceholderChatScreens: ChatScreenProviding {
    func start(host: ChatHost) async throws { }

    func roomScreen(roomID: String, host: ChatHost) -> AnyView {
        AnyView(PlaceholderView(roomID: roomID, host: host, title: nil))
    }

    func threadScreen(roomID: String, rootEventID: String, host: ChatHost) -> AnyView {
        AnyView(PlaceholderView(roomID: roomID, host: host, title: "Thread"))
    }

}

extension ChatScreenProviding {
    func focus(roomID: String, eventID: String) {}

    func threadsEntry(host: ChatHost, open: @escaping () -> Void) -> AnyView {
        AnyView(Button("Threads", action: open).padding())
    }

    /// Until the conversation views bring their thread list, the Threads tab says what comes.
    func threadsScreen(host: ChatHost) -> AnyView {
        AnyView(ContentUnavailableView("Deine Threads", systemImage: "bubble.left",
                                       description: Text("Hier stehen bald alle Threads, in denen du mitredest, die neuesten oben.")))
    }
}

private struct PlaceholderView: View {
    let roomID: String
    let host: ChatHost
    let title: String?
    @State private var name = ""

    var body: some View {
        ContentUnavailableView {
            Label(title ?? name, systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Nachrichten lesen und schreiben kommt mit dem nächsten Build.")
        }
        .navigationTitle(title ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            name = (try? host.client.getRoom(roomId: roomID))?.flatMap { $0.displayName() } ?? ""
        }
    }
}
