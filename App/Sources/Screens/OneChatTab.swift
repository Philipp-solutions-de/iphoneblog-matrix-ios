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

/// #one-Chat: the #one rooms. Members get Threads on top and open a room as a channel;
/// signed-in non-members see the rooms locked, and a tap offers #one.
private struct MemberGate: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @State private var showOffer = false

    var body: some View {
        if session.isOneMember || session.oneRooms.contains(where: \.locked) {
            NavigationStack(path: $router.chatPath) {
                OneRoomsList(session: session, router: router) { showOffer = true }
                    .navigationDestination(for: Router.ChatRoute.self) { route in
                        destination(route)
                    }
            }
            .task(id: session.isOneMember) { await session.loadOneRooms() }
            .sheet(isPresented: $showOffer) {
                LockedOneChat(signedIn: true, router: router).presentationDragIndicator(.visible)
            }
        } else {
            LockedOneChat(signedIn: true, router: router)
                .task(id: session.isOneMember) { await session.loadOneRooms() }
        }
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
            ChatScreens.provider.threadScreen(roomID: thread.roomID, rootEventID: thread.rootEventID, host: session)
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
    let offer: () -> Void

    init(session: ChatSession, router: Router, offer: @escaping () -> Void) {
        self.session = session
        self.router = router
        self.roomList = session.rooms
        self.offer = offer
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if session.isOneMember {
                    // Slack's place for threads: above the rooms, with a count of the ones with news.
                    ChatScreens.provider.threadsEntry(host: session) { router.openThreadsList() }
                }
                ForEach(session.oneRooms) { room in
                    Button {
                        if room.locked || !session.isOneMember { offer() } else { router.chatPath.append(.room(room.id)) }
                    } label: {
                        OneRoomRow(room: room, unread: unread(room.id), locked: room.locked || !session.isOneMember)
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
            if session.isOneMember {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.openSearch(in: session.oneRooms.map(\.id)) } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("In #one-Chat suchen")
                        .accessibilityIdentifier("chat-search")
                }
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

/// One #one room: "# Allgemein", its topic, unread count or lock.
private struct OneRoomRow: View {
    let room: ChatSession.OneRoom
    let unread: Int
    let locked: Bool

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
            if locked {
                Image(systemName: "lock").foregroundStyle(Theme.coral).accessibilityLabel("Nur für #one-Mitglieder")
            } else if unread > 0 {
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

/// "Nur für #one-Mitglieder" (preview 3c).
struct LockedOneChat: View {
    let signedIn: Bool
    @ObservedObject var router: Router

    var body: some View {
        VStack(spacing: 0) {
            // The channel's one name, as everywhere: "#one-Chat" ("#one" in the #one colour).
            (Text("#one").foregroundStyle(Theme.coral) + Text("-Chat").foregroundStyle(Theme.ink))
                .font(.system(size: 24, weight: .medium))
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
