import SwiftUI

/// The #one tab's root for members (variant A, Thorsten 2026-11-18; spec-ios.md "Screens"):
/// "Neu für dich" with the newest episode, the tiles Chat and Videos, "Gerade aktiv" with the
/// one or two rooms that moved last. Video only in v1.
struct OneHubView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject var episodes: EpisodesModel
    @ObservedObject private var roomList: RoomListModel
    @ObservedObject private var progress = PlaybackProgress.shared

    init(session: ChatSession, router: Router, episodes: EpisodesModel) {
        self.session = session
        self.router = router
        self.episodes = episodes
        roomList = session.rooms
    }

    private func summary(_ id: String) -> RoomSummary? { roomList.rooms.first { $0.id == id } }

    /// Only #one's rooms count; direct messages show in Für dich (spec "Counts").
    private var chatUnread: Int {
        var sum = 0
        for room in session.oneRooms { sum += summary(room.id)?.unreadMessages ?? 0 }
        return sum
    }

    private struct Active: Identifiable {
        let room: ChatSession.OneRoom
        let summary: RoomSummary
        var id: String { room.id }
    }

    /// The one or two #one rooms that moved last.
    private var active: [Active] {
        var list: [Active] = []
        for room in session.oneRooms {
            if let found = summary(room.id), found.lastActivity != nil { list.append(Active(room: room, summary: found)) }
        }
        list.sort { ($0.summary.lastActivity ?? 0) > ($1.summary.lastActivity ?? 0) }
        return Array(list.prefix(2))
    }

    /// Episodes are shown once the route answered with some; a missing route (404) or an error
    /// leaves the chat parts alone.
    private var showsEpisodes: Bool { !episodes.episodes.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let newest = episodes.episodes.first {
                    HubSection("Neu für dich")
                    Button { router.chatPath.append(.episode(newest)) } label: {
                        HeroCard(episode: newest, entry: progress.entry(newest.videoID))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hub.hero")
                } else if !episodes.hasLoaded {
                    HubSection("Neu für dich")
                    RoundedRectangle(cornerRadius: Theme.Size.corner).fill(Theme.surface)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .padding(.horizontal, Theme.Space.page)
                        .accessibilityHidden(true)
                }

                HubSection("Bereiche")
                HStack(spacing: 10) {
                    Button { router.openChat() } label: {
                        HubTile(icon: "bubble.left.and.bubble.right", title: "Chat",
                                detail: session.oneRooms.count == 1 ? "1 Raum" : "\(session.oneRooms.count) Räume", badge: chatUnread)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chat, \(session.oneRooms.count) Räume" + (chatUnread > 0 ? ", \(chatUnread) ungelesen" : ""))
                    .accessibilityIdentifier("hub.tile.chat")
                    if showsEpisodes {
                        Button { router.chatPath.append(.videos) } label: {
                            HubTile(icon: "play.rectangle", title: "Videos", detail: "\(max(episodes.total, episodes.episodes.count))", badge: 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Videos, \(max(episodes.total, episodes.episodes.count)) Folgen")
                        .accessibilityIdentifier("hub.tile.videos")
                    }
                }
                .padding(.horizontal, Theme.Space.page)

                if !active.isEmpty {
                    HubSection("Gerade aktiv") {
                        Button("Alle") { router.openChat() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.teal)
                            .accessibilityLabel("Alle Räume")
                            .accessibilityIdentifier("hub.active.all")
                    }
                    VStack(spacing: 0) {
                        ForEach(active) { item in
                            Button { router.openChat(roomID: item.room.id) } label: {
                                ActiveRow(name: item.room.name, summary: item.summary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("hub.active.\(item.room.name)")
                        }
                    }
                    .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.Size.corner))
                    .padding(.horizontal, Theme.Space.page)
                }
            }
            .padding(.bottom, 24)
            // With "#one" in the navigation bar the content began 8 pt lower than with the old
            // header in the page; it starts where it did (measured 2026-11-20).
            .padding(.top, -8)
        }
        .background(Theme.background)
        .navigationTitle("#one")
        .navigationBarTitleDisplayMode(.inline)
        // The hub keeps a navigation bar, with "#one" and the search in it. Hidden here and shown
        // in the room, the bar made the back button jump to the screen's edge when a back swipe
        // was let go (Philip, 2026-11-20); with a bar on both screens it moves as the system's.
        .toolbar {
            // A title, not a button: no glass capsule behind it (iOS 26).
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { hubTitle }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { hubTitle }
            }
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            // The search keeps the hub's own small circle, not the bar's glass button.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { hubSearch }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { hubSearch }
            }
        }
        .task { await episodes.load() }
        .refreshable { await episodes.load() }
    }
}

extension OneHubView {
    fileprivate var hubSearch: some View {
        // The search over blog and #one (ADR-0010); a room's own magnifier keeps Matrix's search.
        Button { router.showSiteSearch = true } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suchen")
        .accessibilityIdentifier("hub.search")
    }

    fileprivate var hubTitle: some View {
        Text("#one")
            .font(Theme.Font.screenTitle)
            .foregroundStyle(Theme.coralText)
            .accessibilityAddTraits(.isHeader)
            .fixedSize()
    }
}

/// A small section title, with an optional action on the right ("Alle").
struct HubSection<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            accessory
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

extension HubSection where Accessory == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

/// The poster, 16:9, with the duration, "Neu" while unwatched and a progress bar once started.
struct EpisodePoster: View {
    let episode: Episode
    let entry: PlaybackProgress.Entry?
    var showsNew = true
    var corner: CGFloat = Theme.Size.corner

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.tealSoft)
            Image(systemName: "play.rectangle.fill").font(.system(size: 34)).foregroundStyle(Theme.teal.opacity(0.5))
            if let poster = episode.poster {
                AsyncImage(url: poster) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if let seconds = entry?.duration ?? episode.durationS.map(Double.init), seconds > 0 {
                Text(Episode.duration(seconds))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
                    .padding(.bottom, entry?.started == true ? 4 : 0)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsNew, entry == nil {
                Text("Neu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.coralButton, in: Capsule())
                    .padding(8)
                    .accessibilityIdentifier("episode.new")
            }
        }
        .overlay(alignment: .bottom) {
            if let entry, entry.started {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.35))
                        Rectangle().fill(Theme.coral).frame(width: proxy.size.width * entry.fraction)
                    }
                }
                .frame(height: 4)
                .accessibilityIdentifier("episode.progress")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .contentShape(RoundedRectangle(cornerRadius: corner))
    }
}

private struct HeroCard: View {
    let episode: Episode
    let entry: PlaybackProgress.Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EpisodePoster(episode: episode, entry: entry)
            Text(["Video", episode.numberLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.coralText)
                .padding(.top, 4)
            Text(episode.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Label(resume, systemImage: entry?.finished == true ? "checkmark" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                    .accessibilityIdentifier("hub.hero.resume")
                Text(episode.dateLabel).font(Theme.Font.footnote).foregroundStyle(Theme.ink3)
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// As the Videos list says it: "Weiter ab 6:12", "Gesehen" (from 95 %), else "Ansehen".
    private var resume: String {
        if let entry, entry.started { return "Weiter ab \(Episode.duration(entry.position))" }
        if entry?.finished == true { return "Gesehen" }
        return "Ansehen"
    }
}

private struct HubTile: View {
    let icon: String
    let title: String
    let detail: String
    let badge: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.teal)
                .frame(width: 36, height: 36)
                .background(Theme.tealSoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
            if badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Theme.coralButton, in: Capsule())
                    .accessibilityIdentifier("hub.tile.chat.badge")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.Size.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.Size.corner).stroke(Theme.line, lineWidth: 1))
    }
}

private struct ActiveRow: View {
    let name: String
    let summary: RoomSummary

    var body: some View {
        // No "#" tile on the left: the name says "# bugs" already (Philip, 2026-11-20).
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("# \(name)" + (summary.unreadMessages > 0 ? " · \(summary.unreadMessages > 99 ? "99+" : "\(summary.unreadMessages)") neu" : ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let line = summary.lastLine {
                    (Text("\(summary.lastSender ?? ""): ").bold() + Text(line))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if summary.unreadMessages > 0 {
                Text(summary.unreadMessages > 99 ? "99+" : "\(summary.unreadMessages)")
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Theme.coralButton, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
