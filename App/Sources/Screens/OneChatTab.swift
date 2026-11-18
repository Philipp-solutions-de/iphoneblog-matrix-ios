import SwiftUI

/// The #one-Chat tab for everyone (Thorsten, 2026-11-16): members get the #one rooms; signed
/// out, a neutral sign-in; signed in without #one, "Nur für #one-Mitglieder" with the account
/// actions Apple asks for (there is no Ich tab for them). No price, no way to buy, no hint.
struct OneChatGate: View {
    @ObservedObject var router: Router
    let session: ChatSession?

    var body: some View {
        if let session, router.isMember {
            OneChatTab(router: router, session: session)
        } else if let session {
            OneMembersOnly(session: session, router: router)
        } else {
            OneSignIn(router: router)
        }
    }
}

/// Signed out: what #one-Chat is, and the way in.
struct OneSignIn: View {
    @ObservedObject var router: Router

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            OneChatTitle()
            Text("Der Chat für #one-Mitglieder.")
                .font(Theme.Font.reading)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            Button { router.showSignIn = true } label: {
                Text("Anmelden").frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
            }
            .buttonStyle(FilledButton(fill: Theme.coralButton))
            .accessibilityIdentifier("one.signIn")
            .padding(.top, 8)
            Spacer()
            LegalLinks(router: router)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Signed in without #one: said plainly, with sign-out and account deletion (App Store 5.1.1(v)).
struct OneMembersOnly: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @State private var confirmSignOut = false
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            OneChatTitle()
            Text("Nur für #one-Mitglieder")
                .font(.system(size: 22))
                .foregroundStyle(Theme.ink)
            Text("Angemeldet als \(session.displayName ?? MentionsModel.localpart(session.userID)).")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink3)
            Spacer()
            VStack(spacing: 10) {
                Button { confirmSignOut = true } label: {
                    Text("Abmelden").frame(maxWidth: .infinity, minHeight: Theme.Size.smallButtonHeight)
                }
                .buttonStyle(OutlineButton(stroke: Theme.line, text: Theme.coralText))
                .accessibilityIdentifier("one.signOut")
                Button { deleting = true } label: {
                    Text("Konto löschen").frame(maxWidth: .infinity, minHeight: Theme.Size.smallButtonHeight)
                }
                .buttonStyle(OutlineButton(stroke: Theme.line, text: Theme.ink2))
                .accessibilityIdentifier("one.deleteAccount")
            }
            LegalLinks(router: router)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .confirmationDialog("Auf diesem Gerät abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await model.signOut() } }
        }
        .sheet(isPresented: $deleting) { AccountDeletionSheet(model: model, router: router) }
    }
}

/// "#one-Chat" as a title, "#one" in the #one colour.
private struct OneChatTitle: View {
    var body: some View {
        (Text("#one").foregroundStyle(Theme.coral) + Text("-Chat").foregroundStyle(Theme.ink))
            .font(.system(size: 30, weight: .semibold))
    }
}

/// Datenschutz and Impressum, for those who have no Ich tab.
private struct LegalLinks: View {
    @ObservedObject var router: Router

    var body: some View {
        HStack(spacing: 18) {
            Button("Datenschutz") { if let url = URL(string: Brand.oauthPolicyURI) { router.presentedURL = url } }
            Button("Impressum") { if let url = URL(string: Brand.imprintURL) { router.presentedURL = url } }
        }
        .font(Theme.Font.footnote)
        .foregroundStyle(Theme.ink3)
        .padding(.bottom, 20)
    }
}

/// #one-Chat for #one members: the #one rooms, Threads on top; a room opens as a channel.
struct OneChatTab: View {
    @ObservedObject var router: Router
    @ObservedObject var session: ChatSession

    var body: some View {
        NavigationStack(path: $router.chatPath) {
            OneRoomsList(session: session, router: router)
                .safeAreaInset(edge: .top) { PushPrimerSlot() }
                .navigationDestination(for: Router.ChatRoute.self) { route in
                    destination(route)
                }
        }
        .task(id: session.isOneMember) { await session.loadOneRooms() }
    }

    @ViewBuilder
    private func destination(_ route: Router.ChatRoute) -> some View {
        switch route {
        case .room(let roomID):
            ChatScreens.provider.roomScreen(roomID: roomID, host: session)
                .id(roomID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { router.openSearch(in: [roomID]) } label: { Image(systemName: "magnifyingglass") }
                            .accessibilityLabel("In diesem Raum suchen")
                            .accessibilityIdentifier("room-search")
                    }
                }
        case .thread(let thread):
            ResolvedThreadScreen(thread: thread, session: session, router: router)
        case .threads:
            ChatScreens.provider.threadsScreen(host: session)
                .navigationTitle("Threads")
                .navigationBarTitleDisplayMode(.inline)
        case .search(let roomIDs):
            ChatSearchView(model: ChatSearchModel(session: session, roomIDs: roomIDs), router: router)
        }
    }
}

/// The list: "#one-Chat" with a search over all rooms, Threads, then each room with its unread
/// count (members) or a lock (non-members).
private struct OneRoomsList: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject private var roomList: RoomListModel

    init(session: ChatSession, router: Router) {
        self.session = session
        self.router = router
        self.roomList = session.rooms
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Slack's place for threads: above the rooms, with a count of the ones with news.
                ChatScreens.provider.threadsEntry(host: session) { router.openThreadsList() }
                ForEach(session.oneRooms) { room in
                    Button { router.chatPath.append(.room(room.id)) } label: {
                        OneRoomRow(room: room, unread: unread(room.id))
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Theme.line).padding(.leading, Theme.Space.page)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("#one-Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.openSearch(in: session.oneRooms.map(\.id)) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("In #one-Chat suchen")
                    .accessibilityIdentifier("chat-search")
            }
        }
        .overlay {
            if session.oneRooms.isEmpty { ProgressView() }
        }
        .refreshable { await session.loadOneRooms() }
    }

    private func unread(_ roomID: String) -> Int {
        roomList.rooms.first { $0.id == roomID }?.unreadMessages ?? 0
    }
}

/// One #one room: "# Allgemein", its topic, its unread count.
private struct OneRoomRow: View {
    let room: ChatSession.OneRoom
    let unread: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("#").font(Theme.Font.rowHash).foregroundStyle(Theme.ink3).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(Theme.Font.rowTitle.weight(unread > 0 ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                if let topic = room.topic, !topic.isEmpty {
                    Text(topic).font(Theme.Font.footnote).foregroundStyle(Theme.ink3).lineLimit(1)
                }
            }
            Spacer()
            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Theme.badge, in: Capsule())
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("one-room")
    }
}
