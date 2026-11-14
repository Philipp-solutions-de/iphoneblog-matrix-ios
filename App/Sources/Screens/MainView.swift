import SafariServices
import SwiftUI

/// The four tabs: Chats, Threads, Erwähnungen, Ich.
struct MainView: View {
    let session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject var rooms: RoomListModel

    var body: some View {
        TabView(selection: $router.tab) {
            ChatsView(session: session, router: router, rooms: rooms)
                .tabItem { Label("Chats", systemImage: "text.alignleft") }
                .tag(Router.Tab.chats)
                .badge(rooms.badgeCount)

            ThreadsView()
                .tabItem { Label("Threads", systemImage: "bubble.left") }
                .tag(Router.Tab.threads)

            MentionsView(router: router, rooms: rooms)
                .tabItem { Label("Erwähnungen", systemImage: "at") }
                .tag(Router.Tab.mentions)

            MeView(session: session)
                .tabItem { Label("Ich", systemImage: "person") }
                .tag(Router.Tab.me)
        }
        .sheet(item: $router.presentedURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// In-app Safari for links in messages and for the account and privacy pages.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(named: "BrandTeal")
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) { }
}
