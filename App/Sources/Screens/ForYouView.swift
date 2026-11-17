import SwiftUI

/// "Für dich" (Thorsten, 2026-11-17): mentions, threads you are in with new replies, and the
/// #one rooms with news, newest first. "Alles · Erwähnungen · Threads" on top; "Alle gelesen"
/// clears exactly what the filter shows. A tap opens the place: the thread at the reply, the
/// room at the message, the article's discussion.
struct ForYouView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var model: ForYouModel
    @ObservedObject var router: Router
    @State private var filter: ForYouModel.Filter = .all

    private var items: [ForYouModel.Item] { model.items(filter) }
    private var showsRooms: Bool { filter == .all && !model.rooms.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ScreenTitle("Für dich")
                if model.unreadCount(filter) > 0 {
                    Button("Alle gelesen") { Task { await model.markAllRead(filter) } }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.teal)
                        .padding(.trailing, Theme.Space.page)
                        .accessibilityIdentifier("foryou.markAllRead")
                }
            }
            Picker("Anzeigen", selection: $filter) {
                ForEach(ForYouModel.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Space.page)
            .padding(.bottom, 8)
            .accessibilityIdentifier("foryou.filter")

            if items.isEmpty, !showsRooms {
                if session.mentions.hasLoaded {
                    ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle",
                                           description: Text("Wenn dich jemand erwähnt oder in deinen Threads antwortet, steht es hier."))
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if showsRooms {
                            ForEach(model.rooms) { room in
                                Button { router.openRoom(room.id) } label: { RoomNewsRow(room: room) }
                                    .buttonStyle(.plain)
                                Divider().overlay(Theme.line)
                            }
                        }
                        ForEach(items) { item in
                            Button { open(item) } label: { row(item) }
                                .buttonStyle(.plain)
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .refreshable { session.mentions.reload() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .onAppear { session.mentions.reload() }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "Alles gelesen"
        case .mentions: "Keine Erwähnungen"
        case .threads: "Noch keine Threads"
        }
    }

    @ViewBuilder
    private func row(_ item: ForYouModel.Item) -> some View {
        switch item {
        case .mention(let mention): MentionRow(mention: mention, me: myNames)
        case .thread(let thread): ThreadNewsRow(thread: thread)
        }
    }

    private func open(_ item: ForYouModel.Item) {
        switch item {
        case .mention(let mention): router.open(mention)
        case .thread(let thread): router.openThread(roomID: thread.roomID, rootEventID: thread.rootEventID)
        }
    }

    /// The words that mark me in a message: "@Tim", "Tim B.", "tim".
    private var myNames: [String] {
        [session.displayName, MentionsModel.localpart(session.userID)].compactMap { $0 }.filter { !$0.isEmpty }
    }
}

/// A thread you are in: the room, who wrote last and what, the thread's start below.
struct ThreadNewsRow: View {
    let thread: InvolvedThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MemberAvatar(userID: thread.latestSenderID ?? "", name: thread.latestSenderName ?? "?", roomID: thread.roomID,
                         size: Theme.Size.chatAvatar, corner: Theme.Size.chatAvatarCorner)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("# \(thread.roomName) · Thread")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.teal)
                        .lineLimit(1)
                    Text("·").foregroundStyle(Theme.ink3).accessibilityHidden(true)
                    Text(MentionRow.shortTime(thread.lastActivity))
                        .font(Theme.Font.time)
                        .foregroundStyle(Theme.ink3)
                    Spacer(minLength: 4)
                    if thread.isUnread {
                        Circle().fill(Theme.teal)
                            .frame(width: Theme.Size.unreadDot, height: Theme.Size.unreadDot)
                            .accessibilityLabel("ungelesen")
                    }
                }
                if let name = thread.latestSenderName {
                    Text(name).font(Theme.Font.name).foregroundStyle(Theme.ink)
                }
                if let latest = thread.latestText {
                    Text(latest)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Text(thread.rootText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, 12)
        .background(thread.isUnread ? Theme.teal.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("foryou.thread")
    }
}

/// A #one room with unread messages, on top of "Alles".
struct RoomNewsRow: View {
    let room: ForYouModel.RoomNews

    var body: some View {
        HStack(spacing: 12) {
            Text("#")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.teal)
                .frame(width: Theme.Size.chatAvatar)
            Text(room.name)
                .font(Theme.Font.name)
                .foregroundStyle(Theme.ink)
            Spacer()
            if room.mentions > 0 {
                Text("@").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.teal)
            }
            Text(room.unread > 99 ? "99+ neu" : "\(room.unread) neu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.teal)
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.name), \(room.unread) ungelesen")
        .accessibilityIdentifier("foryou.room")
    }
}
