import SwiftUI

/// #one-Chat (previews 3a to 3c): one channel, Allgemein, for #one members. Everyone else sees
/// it locked, with the way to #one.
struct OneChatTab: View {
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?

    var body: some View {
        if let session {
            MemberGate(session: session, router: router)
        } else {
            LockedOneChat(signedIn: false, router: router)
        }
    }
}

/// Decides per sync whether the channel or the lock shows.
private struct MemberGate: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router

    var body: some View {
        if session.isOneMember, let channel = session.oneChannelID {
            NavigationStack(path: $router.threadPath) {
                VStack(spacing: 0) {
                    // Slack's place for threads: above the channel, with a count of the ones with news.
                    ChatScreens.provider.threadsEntry(host: session) { router.showThreads = true }
                    ChatScreens.provider.roomScreen(roomID: channel, host: session)
                        .id(channel)
                }
                .navigationDestination(for: Router.ThreadRoute.self) { route in
                    ChatScreens.provider.threadScreen(roomID: route.roomID, rootEventID: route.rootEventID, host: session)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { router.showSearch = true } label: { Image(systemName: "magnifyingglass") }
                            .accessibilityLabel("In #one-Chat suchen")
                            .accessibilityIdentifier("chat-search")
                    }
                }
                .navigationDestination(isPresented: $router.showSearch) {
                    ChatSearchView(model: ChatSearchModel(session: session, roomIDs: [channel]), router: router)
                }
                .navigationDestination(isPresented: $router.showThreads) {
                    ChatScreens.provider.threadsScreen(host: session)
                        .navigationTitle("Threads")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .onAppear { router.selectedRoomID = channel }
            .task(id: router.pendingThread) {
                guard let route = router.pendingThread else { return }
                // One frame for the stack to settle after the tab change.
                try? await Task.sleep(for: .milliseconds(150))
                router.threadPath = [route]
                router.pendingThread = nil
            }
        } else {
            LockedOneChat(signedIn: true, router: router)
        }
    }
}

/// "Nur für #one-Mitglieder" (preview 3c).
struct LockedOneChat: View {
    let signedIn: Bool
    @ObservedObject var router: Router

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#one-Chat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text("Allgemein")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, 6)
            .padding(.bottom, 12)
            Divider().overlay(Theme.line)

            VStack(spacing: 16) {
                Image(systemName: "lock")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Theme.coral)
                    .frame(width: Theme.Size.lockCircle, height: Theme.Size.lockCircle)
                    .background(Theme.coralSoft, in: Circle())
                (Text("Nur für ") + Text("#one").foregroundStyle(Theme.coral) + Text("-Mitglieder"))
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("Hier schreiben die Abonnentinnen und Abonnenten von iPhoneBlog #one miteinander. Dazu gibt es jede Woche ein „Gewusst-wie“-Video und einen Mini-Podcast.")
                    .font(Theme.Font.reading)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: Brand.oneOfferURL) { router.presentedURL = url }
                } label: {
                    Text("#one abonnieren").frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
                }
                .buttonStyle(FilledButton(fill: Theme.coralButton))
                .padding(.top, 8)
                if !signedIn {
                    Button("Schon Mitglied? Anmelden") { router.showSignIn = true }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.coralText)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 70)
            .frame(maxWidth: 480)
            Spacer()
        }
        .background(Theme.background)
    }
}
