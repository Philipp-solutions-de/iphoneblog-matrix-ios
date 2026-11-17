import Combine
import Foundation

/// "Für dich" (Thorsten, 2026-11-17): what concerns me, in one list, newest first. Mentions of me
/// (@me, @room; a reply to my message carries one), new replies in threads I take part in (#one
/// and the Blog's discussions), and the #one rooms with unread messages. The tab's badge counts
/// unread mentions and threads with new replies; unread room messages show on the #one tab.
@MainActor
final class ForYouModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alles"
        case mentions = "Erwähnungen"
        case threads = "Threads"
        var id: String { rawValue }
    }

    enum Item: Identifiable, Equatable {
        case mention(MentionsModel.Mention)
        case thread(InvolvedThread)

        var id: String {
            switch self {
            case .mention(let mention): "m:" + mention.id
            case .thread(let thread): "t:" + thread.id
            }
        }

        var date: Date {
            switch self {
            case .mention(let mention): mention.date
            case .thread(let thread): thread.lastActivity
            }
        }

        var isUnread: Bool {
            switch self {
            case .mention(let mention): mention.unread
            case .thread(let thread): thread.isUnread
            }
        }
    }

    /// A #one room with unread messages, for "Alles".
    struct RoomNews: Identifiable, Equatable {
        let id: String
        let name: String
        let unread: Int
        let mentions: Int
    }

    @Published private(set) var threads: [InvolvedThread] = []
    @Published private(set) var rooms: [RoomNews] = []
    @Published private(set) var mentionItems: [MentionsModel.Mention] = []

    private weak var session: ChatSession?
    private var watches = Set<AnyCancellable>()

    func attach(to session: ChatSession) {
        self.session = session
        session.mentions.$items
            .sink { [weak self] in self?.mentionItems = $0 }
            .store(in: &watches)
        ChatScreens.provider.involvedThreads()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.threads = $0 }
            .store(in: &watches)
        session.rooms.$rooms.combineLatest(session.rooms.$channelIDs)
            .map { rooms, channels in
                rooms.filter { channels.contains($0.id) && $0.unreadMessages > 0 }
                    .map { RoomNews(id: $0.id, name: $0.name, unread: $0.unreadMessages, mentions: $0.unreadMentions) }
            }
            .removeDuplicates()
            .sink { [weak self] in self?.rooms = $0 }
            .store(in: &watches)
    }

    /// The list under a filter, newest first. Threads show only when they have news or once
    /// had; a thread with no new replies stays out of "Alles" to keep it about what is new.
    func items(_ filter: Filter) -> [Item] {
        let mentions = mentionItems.map(Item.mention)
        let threads = self.threads.map(Item.thread)
        let all: [Item] = switch filter {
        case .all: mentions + threads.filter(\.isUnread)
        case .mentions: mentions
        case .threads: threads
        }
        return all.sorted { $0.date > $1.date }
    }

    func unreadCount(_ filter: Filter) -> Int {
        items(filter).filter(\.isUnread).count + (filter == .all ? rooms.count : 0)
    }

    /// The tab's badge: unread mentions and threads with new replies.
    var badge: Int {
        mentionItems.filter(\.unread).count + threads.filter(\.isUnread).count
    }

    /// "Alle gelesen" for exactly what the filter shows: mentions through their receipts,
    /// threads as seen, and under "Alles" the rooms up to their newest message too.
    func markAllRead(_ filter: Filter) async {
        guard let session else { return }
        if filter != .threads { await session.mentions.markAllRead() }
        if filter != .mentions {
            let unread = threads.filter(\.isUnread)
            if !unread.isEmpty { ChatScreens.provider.markThreadsSeen(unread) }
        }
        if filter == .all {
            for room in rooms {
                try? await session.client.getRoom(roomId: room.id)?.markAsRead(receiptType: .read)
            }
        }
    }
}
