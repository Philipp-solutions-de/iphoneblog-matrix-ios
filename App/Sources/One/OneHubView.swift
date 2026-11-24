import SwiftUI

/// The #one tab's root for members, draft B (Thorsten, 2026-11-20: "The middle one (B). The
/// videos at the top with 'coverflow'"): the newest episodes as a cover flow, then Threads and
/// the rooms with their last message. A tap opens the episode, the Threads list or the room in
/// Chat under the room bar. It replaces the hub of 2026-11-18 (Neu für dich, Bereiche, Gerade
/// aktiv).
struct OneHubView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject var episodes: EpisodesModel
    @ObservedObject private var roomList: RoomListModel
    @ObservedObject private var forYou: ForYouModel
    @ObservedObject private var progress = PlaybackProgress.shared

    init(session: ChatSession, router: Router, episodes: EpisodesModel) {
        self.session = session
        self.router = router
        self.episodes = episodes
        roomList = session.rooms
        forYou = session.forYou
    }

    private func summary(_ id: String) -> RoomSummary? { roomList.rooms.first { $0.id == id } }

    /// The threads you take part in, in #one's rooms, newest first.
    private var threads: [InvolvedThread] {
        let rooms = Set(session.oneRooms.map(\.id))
        return forYou.threads.filter { rooms.contains($0.roomID) }.sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Episodes once the route answered with some; until then, or without the route,
                // the rooms alone.
                if !episodes.episodes.isEmpty {
                    HubSection("Videos") {
                        Button("Alle") { router.chatPath.append(.videos) }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.teal)
                            .accessibilityLabel("Alle Videos, \(max(episodes.total, episodes.episodes.count)) Folgen")
                            .accessibilityIdentifier("one.videos.all")
                    }
                    EpisodeCoverFlow(episodes: Array(episodes.episodes.prefix(8)), progress: progress) { episode in
                        router.chatPath.append(.episode(episode))
                    }
                } else if !episodes.hasLoaded {
                    HubSection("Videos")
                    RoundedRectangle(cornerRadius: Theme.Size.corner).fill(Theme.surface)
                        .frame(width: EpisodeCoverFlow.cardWidth)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                HubSection("Räume")
                VStack(spacing: 0) {
                    if let latest = threads.first {
                        Button { router.openThreadsList() } label: {
                            OneRow(icon: .threads, title: "Threads", time: OneRow.time(latest.lastActivity),
                                   sender: latest.latestSenderName ?? latest.rootSenderName,
                                   line: latest.replies == 1 ? "1 Antwort" : "\(latest.replies) Antworten",
                                   badge: threads.filter(\.isUnread).count, mention: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("one.threads")
                    }
                    ForEach(session.oneRooms) { room in
                        let found = summary(room.id)
                        Button { router.openChat(roomID: room.id) } label: {
                            OneRow(icon: .room, title: "# \(room.name)",
                                   time: found?.lastActivity.map { OneRow.time(Date(timeIntervalSince1970: Double($0) / 1000)) },
                                   sender: found?.lastSender, line: found?.lastLine,
                                   badge: found?.unreadMessages ?? 0, mention: (found?.unreadMentions ?? 0) > 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("one.room.\(room.name)")
                    }
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
        // The root keeps a navigation bar, with "#one" and the search in it. Hidden here and
        // shown on the next screen, the bar made the back button jump to the screen's edge when a
        // back swipe was let go (Philip, 2026-11-20); with a bar on both it moves as the system's.
        .toolbar {
            // A title, not a button: no glass capsule behind it (iOS 26).
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { hubTitle }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { hubTitle }
            }
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            // The search keeps its own small circle, not the bar's glass button.
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

/// The newest episodes as a cover flow: the centred one full size, its neighbours smaller and
/// turned towards it, snapping to the centre. Reduce Motion gets the same row flat.
struct EpisodeCoverFlow: View {
    static let cardWidth: CGFloat = 262
    let episodes: [Episode]
    @ObservedObject var progress: PlaybackProgress
    let open: (Episode) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(episodes) { episode in
                        Button { open(episode) } label: {
                            EpisodeCard(episode: episode, entry: progress.entry(episode.videoID))
                        }
                        .buttonStyle(.plain)
                        .frame(width: Self.cardWidth)
                        .accessibilityIdentifier("one.episode")
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.14)
                                .rotation3DEffect(.degrees(reduceMotion ? 0 : phase.value * -32),
                                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                                .opacity(reduceMotion ? 1 : 1 - abs(phase.value) * 0.25)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            // The first episode starts in the centre, the next ones peek in from the right.
            .contentMargins(.horizontal, max(Theme.Space.page, (proxy.size.width - Self.cardWidth) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
        .frame(height: EpisodeCard.height)
        .accessibilityIdentifier("one.coverflow")
    }
}

/// One episode in the cover flow: poster, "Folge N", the title, and "Weiter ab", "Gesehen" or
/// the date.
struct EpisodeCard: View {
    static let height: CGFloat = 147 + 74
    let episode: Episode
    let entry: PlaybackProgress.Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EpisodePoster(episode: episode, entry: entry)
            if let number = episode.numberLabel {
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.coralText)
                    .padding(.top, 6)
            }
            Text(episode.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, episode.numberLabel == nil ? 6 : 0)
            Text(status)
                .font(.system(size: 14, weight: entry?.started == true ? .semibold : .regular))
                .foregroundStyle(entry?.started == true ? Theme.teal : Theme.ink3)
            Spacer(minLength: 0)
        }
        .frame(height: Self.height, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// As the Videos list says it: "Weiter ab 6:12", "Gesehen" (from 95 %), else the date.
    private var status: String {
        if let entry, entry.started { return "Weiter ab \(Episode.duration(entry.position))" }
        if entry?.finished == true { return "Gesehen" }
        return episode.dateLabel
    }
}

/// A row under "Räume": the Threads list or a room, with its newest line and unread count.
private struct OneRow: View {
    enum Icon { case threads, room }
    let icon: Icon
    let title: String
    let time: String?
    let sender: String?
    let line: String?
    let badge: Int
    let mention: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch icon {
                case .threads: Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 19, weight: .semibold))
                case .room: Text("#").font(.system(size: 20, weight: .semibold))
                }
            }
            .foregroundStyle(icon == .threads ? Theme.teal : Theme.ink3)
            .frame(width: 46, height: 46)
            .background(icon == .threads ? Theme.tealSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    if let time { Text(time).font(.system(size: 13.5)).foregroundStyle(Theme.ink3) }
                }
                HStack(spacing: 8) {
                    preview.lineLimit(1)
                    Spacer(minLength: 0)
                    if badge > 0 {
                        Text((mention ? "@" : "") + (badge > 99 ? "99+" : "\(badge)"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Theme.teal, in: Capsule())
                    }
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        }
        .padding(.horizontal, Theme.Space.page)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var preview: Text {
        let text = Text(line ?? "").font(.system(size: 15)).foregroundStyle(Theme.ink3)
        guard let sender else { return text }
        return Text("\(sender): ").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink) + text
    }

    /// "09:12" today, "gestern", else the day ("17. Nov.").
    static func time(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        if calendar.isDateInYesterday(date) { return "gestern" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }
}
