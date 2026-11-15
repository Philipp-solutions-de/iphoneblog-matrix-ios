import SwiftUI

/// The tab bar (preview 1): Blog, #one-Chat, @Mentions (signed in only), Ich.
/// The app opens on Blog, readable without an account; sign-in is offered where writing starts.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?

    var body: some View {
        TabView(selection: $router.tab) {
            BlogTab(router: router, session: session)
                .tabItem { Label("Blog", systemImage: "doc.richtext") }
                .tag(Router.Tab.blog)

            OneChatTab(router: router, session: session)
                .tabItem { Label("#one-Chat", systemImage: "number") }
                .tag(Router.Tab.chat)
                .badge(chatBadge)

            if let session {
                MentionsView(session: session, mentions: session.mentions, router: router)
                    .tabItem { Label("@Mentions", systemImage: "at") }
                    .tag(Router.Tab.mentions)
                    .badge(session.mentions.unreadCount)
            }

            Group {
                if let session {
                    MeView(session: session, prefs: session.notificationPrefs, router: router)
                } else {
                    GuestMeView(router: router)
                }
            }
            .tabItem { Label("Ich", systemImage: "person") }
            .tag(Router.Tab.me)
        }
        .onChange(of: session == nil) { _, signedOut in
            if signedOut, router.tab == .mentions { router.tab = .blog }
        }
        .sheet(item: $router.presentedURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        .sheet(isPresented: $router.showSignIn) {
            SignInView()
                .environmentObject(model)
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let notice = router.notice {
                Text(notice)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { router.notice = nil }
                    }
            }
        }
        .animation(.default, value: router.notice)
    }

    /// #one-Chat counts unread messages in the channel, for members.
    private var chatBadge: Int {
        guard let session, session.isOneMember, let channel = session.oneChannelID else { return 0 }
        return session.rooms.rooms.first { $0.id == channel }?.unreadMessages ?? 0
    }
}
