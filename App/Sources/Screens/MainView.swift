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
    @State private var confirmReadAll = false
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?

    var body: some View {
        TabView(selection: $router.tab) {
            BlogTab(router: router, session: session, web: model.blogWeb)
                .tabItem { Label("Blog", systemImage: "doc.richtext") }
                .tag(Router.Tab.blog)

            // #one for everyone: the rooms for members, otherwise sign-in or "Nur für
            // #one-Mitglieder". Für dich and Ich for members only (Thorsten, 2026-11-16/17).
            OneChatGate(router: router, session: session)
                // One "#": the big symbol; the label says "one" (Thorsten, 2026-11-20).
                .tabItem { Label("one", systemImage: "number") }
                .tag(Router.Tab.chat)
                .badge(router.chatBadge)

            if let session, router.isMember {
                ForYouView(session: session, model: session.forYou, router: router)
                    .tabItem { Label("Für dich", systemImage: "bell") }
                    .tag(Router.Tab.forYou)
                    .badge(router.forYouBadge)

                MeView(session: session, prefs: session.notificationPrefs, router: router)
                    .tabItem { Label("Ich", systemImage: "person") }
                    .tag(Router.Tab.me)
            }
        }
        // The selected tab in teal, the selected "one" in the #one red (Philip's point, approved;
        // Thorsten's #one tint, 2026-11-20). Only the selected item takes the tint.
        .tint(router.tab == .chat ? Theme.coral : Theme.teal)
        // A long press on "Für dich": everything read, while there is something (haptic).
        .background {
            if let session, router.isMember {
                TabLongPress(index: 2) {
                    guard router.forYouBadge > 0 else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    confirmReadAll = true
                }
                .frame(width: 0, height: 0)
            }
        }
        // Asked first (Thorsten, 2026-11-19): a long press by accident cleared everything.
        .confirmationDialog("Alle als gelesen markieren?", isPresented: $confirmReadAll, titleVisibility: .visible) {
            Button("Alle als gelesen markieren") {
                guard let session else { return }
                Task {
                    await session.forYou.markAllRead(.all)
                    router.notice = "Alles als gelesen markiert."
                }
            }
            .accessibilityIdentifier("foryou.confirmReadAll")
            Button("Abbrechen", role: .cancel) { }
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
            if signedOut, router.tab == .forYou { router.tab = .blog }
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
                Text("foryou=\(router.forYouBadge) chat=\(router.chatBadge)")
                    .font(.system(size: 1)).opacity(0.02)
                    .accessibilityIdentifier("debug.badges")
            }
        }
        #endif
    }

    /// #one-Chat counts unread messages in the channel, for members.
}
