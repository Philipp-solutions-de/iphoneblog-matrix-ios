import SwiftUI

/// The tab bar (preview 1): Blog, #one-Chat, @Mentions (signed in only), Ich.
/// The app opens on Blog, readable without an account; sign-in is offered where writing starts.
struct MainView: View {
    /// Unread counts on the tabs in teal, not the system red: red is only for #one
    /// (Theme.swift, the colour rule).
    init(router: Router, session: ChatSession?) {
        self.router = router
        self.session = session
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.badgeBackgroundColor = UIColor(Theme.badge)
            item.selected.badgeBackgroundColor = UIColor(Theme.badge)
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBarItem.appearance().badgeColor = UIColor(Theme.badge)
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?

    var body: some View {
        TabView(selection: $router.tab) {
            BlogTab(router: router, session: session)
                .tabItem { Label("Blog", systemImage: "doc.richtext") }
                .tag(Router.Tab.blog)

            // #one-Chat for everyone: the rooms for members, otherwise sign-in or "Nur für
            // #one-Mitglieder". @Mentions and Ich for members only (Thorsten, 2026-11-16).
            OneChatGate(router: router, session: session)
                .tabItem { Label("#one-Chat", systemImage: "number") }
                .tag(Router.Tab.chat)
                .badge(router.chatBadge)

            if let session, router.isMember {
                MentionsView(session: session, mentions: session.mentions, router: router)
                    .tabItem { Label("@Mentions", systemImage: "at") }
                    .tag(Router.Tab.mentions)
                    .badge(router.mentionsBadge)

                MeView(session: session, prefs: session.notificationPrefs, router: router)
                    .tabItem { Label("Ich", systemImage: "person") }
                    .tag(Router.Tab.me)
            }
        }
        // Sync stops in the background and starts again in front (ChatSession).
        .onChange(of: scenePhase) { _, phase in
            guard let session else { return }
            switch phase {
            case .background: Task { await session.enterBackground() }
            case .active: Task { await session.enterForeground() }
            default: break
            }
        }
        .onChange(of: session == nil) { _, signedOut in
            if signedOut, router.tab == .mentions { router.tab = .blog }
        }
        // A chat link tapped anywhere in the app (a message, the blog) opens in the app, not in
        // Safari; anything else as before.
        .environment(\.openURL, OpenURLAction { url in model.open(url) ? .handled : .systemAction })
        .sheet(item: $router.presentedURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        // A person: from a tap on a name, an avatar or a mention; a long press shares at once.
        .sheet(item: $router.profile) { person in
            if let session { ProfileSheet(person: person, session: session, router: router) }
        }
        .sheet(item: $router.moderation) { request in
            if let session { ModerationSheet(request: request, session: session) }
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
        #if DEBUG
        // UI tests read the tab badges here: iOS 26's tab bar does not expose them
        // (IPHONEBLOG_EXPOSE_BADGES=1; debug builds only).
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["IPHONEBLOG_EXPOSE_BADGES"] == "1" {
                Text("mentions=\(router.mentionsBadge) chat=\(router.chatBadge)")
                    .font(.system(size: 1)).opacity(0.02)
                    .accessibilityIdentifier("debug.badges")
            }
        }
        #endif
    }

    /// #one-Chat counts unread messages in the channel, for members.
}
