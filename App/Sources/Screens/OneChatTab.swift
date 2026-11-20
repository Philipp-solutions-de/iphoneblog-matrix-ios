import SwiftUI

/// The #one tab for everyone (Thorsten, 2026-11-16): members get the #one rooms; signed
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

/// Signed out (spec-ios.md "Screens (not a member)"): the "#" mark, "#one", one line and the
/// sign-in. No price, no buy hint, no "Mitglied werden", no link to the offer (App Store
/// reader rule).
struct OneSignIn: View {
    @ObservedObject var router: Router

    var body: some View {
        VStack(spacing: 0) {
            OneGateTitle()
            Spacer()
            VStack(spacing: 14) {
                OneMark()
                Text("#one").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                Text("Melde dich mit deinem iPhoneBlog-Konto an, um #one zu öffnen.")
                    .font(Theme.Font.reading)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("one.gate.text")
                Button { router.showSignIn = true } label: {
                    Text("Anmelden").frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
                }
                .buttonStyle(FilledButton(fill: Theme.coralButton))
                .accessibilityIdentifier("one.signIn")
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            Spacer()
            LegalLinks(router: router)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Signed in without #one (spec): "Kein Zugang zu #one", the account's name, and a way to use
/// another account. Account deletion stays reachable as a quiet link: there is no Ich tab
/// for them (App Store 5.1.1(v)).
struct OneMembersOnly: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @State private var confirmSwitch = false
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 0) {
            OneGateTitle()
            Spacer()
            VStack(spacing: 14) {
                OneMark()
                Text("Kein Zugang zu #one").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                Text("Das Konto \(session.displayName ?? MentionsModel.localpart(session.userID)) hat keinen Zugang zu #one.")
                    .font(Theme.Font.reading)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("one.gate.text")
                Button { confirmSwitch = true } label: {
                    Text("Mit anderem Konto anmelden").frame(maxWidth: .infinity, minHeight: Theme.Size.smallButtonHeight)
                }
                .buttonStyle(OutlineButton(stroke: Theme.line, text: Theme.ink))
                .accessibilityIdentifier("one.signOut")
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            Spacer()
            Button("Konto löschen") { deleting = true }
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink3)
                .accessibilityIdentifier("one.deleteAccount")
                .padding(.bottom, 10)
            LegalLinks(router: router)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .confirmationDialog("Auf diesem Gerät abmelden und mit einem anderen Konto anmelden?", isPresented: $confirmSwitch, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                Task {
                    await model.signOut()
                    router.tab = .chat
                    router.showSignIn = true
                }
            }
        }
        .sheet(isPresented: $deleting) { AccountDeletionSheet(model: model, router: router) }
    }
}

/// The large title "#one" at the top of the gates, as the hub has it.
private struct OneGateTitle: View {
    var body: some View {
        Text("#one")
            .font(Theme.Font.screenTitle)
            .foregroundStyle(Theme.coralText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The "#" mark in the #one colour.
private struct OneMark: View {
    var body: some View {
        Text("#")
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Theme.Size.lockCircle, height: Theme.Size.lockCircle)
            .background(Theme.coralButton, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
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

/// #one for members: the hub at the root (variant A, Thorsten 2026-11-18), with Chat, Videos and
/// an episode pushed on it. Chat is the room bar from room-nav variant A (Thorsten, 2026-11-17):
/// the #one rooms with their unread counts, the open room below. A tap switches rooms; Chat opens
/// the last room read; the bar's unread dots lead to the next room (no "Weiter" bar, Thorsten
/// 2026-11-20); the search looks in all rooms.
struct OneChatTab: View {
    @ObservedObject var router: Router
    @ObservedObject var session: ChatSession
    @StateObject private var episodes: EpisodesModel
    @StateObject private var players = EpisodePlayers()

    init(router: Router, session: ChatSession) {
        self.router = router
        self.session = session
        _episodes = StateObject(wrappedValue: EpisodesModel(source: EpisodesModel.source { [weak session] in
            await MainActor.run { try? session?.client.session().accessToken }
        }))
    }

    var body: some View {
        NavigationStack(path: $router.chatPath) {
            OneHubView(session: session, router: router, episodes: episodes)
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
        case .chat:
            OneRoomView(session: session, router: router)
        case .videos:
            VideosView(episodes: episodes, router: router)
        case .episode(let episode):
            EpisodeView(episode: episode, player: players.player(for: episode)) { [players] in
                // Only when the page left the stack, not when something covers it.
                if !router.chatPath.contains(.episode(episode)) { players.close(episode) }
            }
        case .room(let roomID):
            ChatScreens.provider.roomScreen(roomID: roomID, host: session).id(roomID)
        case .thread(let thread):
            ResolvedThreadScreen(thread: thread, session: session, router: router)
        case .threads:
            ChatScreens.provider.threadsScreen(host: session)
                .navigationTitle("Threads")
                .navigationBarTitleDisplayMode(.inline)
        case .search(let roomIDs, let current):
            ChatSearchView(model: ChatSearchModel(session: session, roomIDs: roomIDs, current: current), router: router,
                           roomName: session.oneRooms.first { $0.id == current }?.name)
        }
    }
}

/// The room bar and the open room.
private struct OneRoomView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject private var roomList: RoomListModel

    init(session: ChatSession, router: Router) {
        self.session = session
        self.router = router
        roomList = session.rooms
    }

    /// The open room: the last one read, else the first room.
    private var current: String? {
        if let id = router.currentRoomID, session.oneRooms.contains(where: { $0.id == id }) { return id }
        return session.oneRooms.first?.id
    }

    private func summary(_ id: String) -> RoomSummary? { roomList.rooms.first { $0.id == id } }

    var body: some View {
        VStack(spacing: 0) {
            RoomBar(rooms: session.oneRooms, current: current, summary: summary) { router.openRoom($0) }
            if let current {
                ChatScreens.provider.roomScreenUnderBar(roomID: current, host: session)
                    .id(current)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // "Chat" alone: the app shows no room topic anywhere (Thorsten, 2026-11-19); the bar
            // names the room.
            ToolbarItem(placement: .principal) {
                Text("Chat").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.openSearch(in: session.oneRooms.map(\.id), current: current) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("In #one suchen")
                .accessibilityIdentifier("chat-search")
            }
        }
        .onAppear { if router.currentRoomID == nil, let current { router.currentRoomID = current } }
    }
}

/// The #one rooms as chips, tap only (no swipe between rooms). Each shows its unread count, with
/// "@" for a mention and 99+ as the cap. A room with news that is scrolled out of sight leaves a
/// teal dot at that edge.
private struct RoomBar: View {
    let rooms: [ChatSession.OneRoom]
    let current: String?
    let summary: (String) -> RoomSummary?
    let select: (String) -> Void

    @State private var frames: [String: CGRect] = [:]
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func unread(_ id: String) -> Int { summary(id)?.unreadMessages ?? 0 }

    private var hiddenNews: (left: Bool, right: Bool) {
        var left = false, right = false
        for room in rooms where unread(room.id) > 0 && room.id != current {
            guard let frame = frames[room.id] else { continue }
            if frame.minX < 0 { left = true }
            if frame.maxX > width { right = true }
        }
        return (left, right)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(rooms) { room in
                        chip(room)
                            .id(room.id)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("roomBar")) } action: { frames[room.id] = $0 }
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("one.roomBar")
            .onChange(of: current) { _, id in
                guard let id else { return }
                if reduceMotion { proxy.scrollTo(id) } else { withAnimation { proxy.scrollTo(id) } }
            }
        }
        .coordinateSpace(name: "roomBar")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay(alignment: .leading) { if hiddenNews.left { edgeDot.padding(.leading, 3) } }
        .overlay(alignment: .trailing) { if hiddenNews.right { edgeDot.padding(.trailing, 3) } }
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var edgeDot: some View {
        Circle().fill(Theme.teal).frame(width: 8, height: 8)
            .accessibilityElement()
            .accessibilityLabel("Weitere Räume mit Neuem")
            .accessibilityIdentifier("one.roomBar.moreNews")
    }

    private func chip(_ room: ChatSession.OneRoom) -> some View {
        let selected = room.id == current
        let count = unread(room.id)
        let mentions = summary(room.id)?.unreadMentions ?? 0
        return Button { select(room.id) } label: {
            HStack(spacing: 6) {
                Text("# \(room.name)")
                    .font(.system(size: 15, weight: selected || count > 0 ? .semibold : .regular))
                if count > 0 {
                    HStack(spacing: 2) {
                        if mentions > 0 { Text("@") }
                        Text(count > 99 ? "99+" : "\(count)")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? Theme.teal : .white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(selected ? Color.white : Theme.teal, in: Capsule())
                }
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(selected ? Theme.teal : Theme.line.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(room.name), \(count) ungelesen" + (mentions > 0 ? ", Erwähnung" : "") : room.name)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("one-room")
    }
}

