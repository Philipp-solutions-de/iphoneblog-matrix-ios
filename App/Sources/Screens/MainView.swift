import SafariServices
import SwiftUI

/// The four tabs: Blog, #one-Chat, @Erwähnungen, Ich (decisions 2026-11-15).
/// The app opens on Blog, readable without an account; sign-in is offered where writing starts.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var router: Router
    @ObservedObject var guestFeed: GuestBlogFeed
    /// Nil while signed out.
    let session: ChatSession?

    var body: some View {
        TabView(selection: $router.tab) {
            BlogTab(router: router, session: session, guestFeed: guestFeed)
                .tabItem { Label("Blog", systemImage: "newspaper") }
                .tag(Router.Tab.blog)

            Group {
                if let session {
                    OneChatTab(session: session, router: router, rooms: session.rooms)
                } else {
                    SignInGate(router: router, title: "#one-Chat",
                               text: "Der Chat der #one-Mitglieder. Melde dich mit deinem Blog-Konto an.")
                }
            }
            .tabItem { Label("#one-Chat", systemImage: "number") }
            .tag(Router.Tab.chat)
            .badge(session.map { $0.isOneMember ? $0.rooms.badgeCount : 0 } ?? 0)

            Group {
                if let session {
                    MentionsView(router: router, rooms: session.rooms)
                } else {
                    SignInGate(router: router, title: "@Erwähnungen",
                               text: "Hier steht, wo dich jemand erwähnt. Melde dich dafür an.")
                }
            }
            .tabItem { Label("@Erwähnungen", systemImage: "at") }
            .tag(Router.Tab.mentions)

            Group {
                if let session {
                    MeView(session: session)
                } else {
                    GuestMeView(router: router)
                }
            }
            .tabItem { Label("Ich", systemImage: "person") }
            .tag(Router.Tab.me)
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
}

/// #one-Chat for a signed-in person: the channels for members, a locked door for everyone else.
struct OneChatTab: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject var rooms: RoomListModel

    var body: some View {
        if session.isOneMember {
            ChatsView(session: session, router: router, rooms: rooms)
        } else {
            LockedOneChat(router: router)
        }
    }
}

/// What a signed-in non-member sees in #one-Chat.
struct LockedOneChat: View {
    @ObservedObject var router: Router

    var body: some View {
        Gate(icon: "lock", title: "Nur für #one-Mitglieder",
             text: "Im #one-Chat reden die Mitglieder von iPhoneBlog #one miteinander. Den Blog und seine Artikel-Threads liest du auch ohne.") {
            Button("Mehr über #one") {
                if let url = URL(string: Brand.oneOfferURL) { router.presentedURL = url }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// A tab that needs an account, while signed out.
struct SignInGate: View {
    @ObservedObject var router: Router
    let title: String
    let text: String

    var body: some View {
        Gate(icon: "person.crop.circle", title: title, text: text) {
            Button("Mit iphoneblog.de anmelden") { router.showSignIn = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Ich while signed out: sign in, privacy, version.
struct GuestMeView: View {
    @ObservedObject var router: Router

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Mit iphoneblog.de anmelden") { router.showSignIn = true }
                        .fontWeight(.semibold)
                } footer: {
                    Text("Du nutzt dein Konto vom Blog. Wer Mitglied bei #one ist, kann schreiben.")
                }
                Section {
                    if let privacy = URL(string: Brand.oauthPolicyURI) {
                        Button("Datenschutz") { router.presentedURL = privacy }
                    }
                    if let one = URL(string: Brand.oneOfferURL) {
                        Button("Mehr über #one") { router.presentedURL = one }
                    }
                    LabeledContent("Version", value: "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Ich").font(Theme.Font.screenTitle).foregroundStyle(Theme.ink)
                }
            }
        }
    }
}

/// The shared layout of a closed door: icon, title, one paragraph, one action.
struct Gate<Action: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: Theme.Gate.iconSize))
                .foregroundStyle(Theme.teal)
            Text(title)
                .font(Theme.Gate.title)
                .foregroundStyle(Theme.ink)
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            action()
                .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
