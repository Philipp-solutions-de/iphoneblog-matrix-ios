import Foundation
import MatrixRustSDK

/// One row in the channel list.
struct RoomSummary: Identifiable, Equatable {
    let id: String
    var name: String
    var isDirect: Bool
    /// Messages since the last read marker.
    var unreadMessages: Int = 0
    /// Mentions of me since the last read marker. The SDK counts them in the few last events it
    /// holds for a room, so a mention with six or more messages after it drops out; the server's
    /// notification list (as @Mentions reads it) sees them all, and the larger count wins.
    var unreadMentions: Int { max(sdkMentions, serverMentions) }
    var sdkMentions = 0
    var serverMentions = 0
    var isMarkedUnread = false
    /// The newest message: when (ms), who, what. "Gerade aktiv" on the #one hub sorts and shows them.
    var lastActivity: UInt64?
    var lastSender: String?
    var lastLine: String?

    var hasUnread: Bool { unreadMessages > 0 || isMarkedUnread }
}

/// Mirrors the SDK's room list into something SwiftUI can draw.
/// The SDK sends diffs (append, insert, remove, ...); we apply them to `sdkRooms`
/// and rebuild the summaries.
@MainActor
final class RoomListModel: ObservableObject {
    @Published private(set) var rooms: [RoomSummary] = []
    @Published private(set) var hasLoaded = false

    /// Rooms the #one-Chat tab leaves out (the Blog room has its own tab).
    var hidden: Set<String> = []
    /// The #one space's children: the channels #one-Chat shows.
    @Published var channelIDs: Set<String> = []
    /// Unread mentions per room from the server (MentionsModel), merged into each row.
    var serverMentions: [String: Int] = [:] {
        didSet {
            guard serverMentions != oldValue else { return }
            let merged = rooms.map { room in
                var room = room
                room.serverMentions = serverMentions[room.id] ?? 0
                return room
            }
            if merged != rooms { rooms = merged }
        }
    }
    var channels: [RoomSummary] { rooms.filter { !$0.isDirect && !hidden.contains($0.id) && channelIDs.contains($0.id) } }
    var withMentions: [RoomSummary] { rooms.filter { $0.unreadMentions > 0 && !hidden.contains($0.id) } }

    private var sdkRooms: [Room] = []
    private var entries: RoomListEntriesWithDynamicAdaptersResult?
    private var entriesHandle: TaskHandle?
    private var roomList: RoomList?
    private var consumer: Task<Void, Never>?

    func attach(to service: RoomListService) async throws {
        let list = try await service.allRooms()
        roomList = list
        // The SDK calls the listener on its own threads. An AsyncStream keeps the diffs in
        // order and applies them one batch at a time.
        let (stream, continuation) = AsyncStream.makeStream(of: [RoomListEntriesUpdate].self)
        consumer = Task { [weak self] in
            for await updates in stream {
                await self?.apply(updates)
            }
        }
        let result = list.entriesWithDynamicAdapters(pageSize: 500, listener: EntriesListener { updates in
            continuation.yield(updates)
        })
        entries = result
        entriesHandle = result.entriesStream()
        // Joined rooms only; spaces are not part of this app.
        _ = result.controller().setFilter(kind: .all(filters: [.joined, .nonSpace]))
    }

    private func apply(_ updates: [RoomListEntriesUpdate]) async {
        for update in updates {
            switch update {
            case .append(let values): sdkRooms.append(contentsOf: values)
            case .clear: sdkRooms.removeAll()
            case .pushFront(let value): sdkRooms.insert(value, at: 0)
            case .pushBack(let value): sdkRooms.append(value)
            case .popFront: if !sdkRooms.isEmpty { sdkRooms.removeFirst() }
            case .popBack: if !sdkRooms.isEmpty { sdkRooms.removeLast() }
            case .insert(let index, let value): sdkRooms.insert(value, at: min(Int(index), sdkRooms.count))
            case .set(let index, let value): if Int(index) < sdkRooms.count { sdkRooms[Int(index)] = value }
            case .remove(let index): if Int(index) < sdkRooms.count { sdkRooms.remove(at: Int(index)) }
            case .truncate(let length): sdkRooms = Array(sdkRooms.prefix(Int(length)))
            case .reset(let values): sdkRooms = values
            }
        }
        var summaries: [RoomSummary] = []
        for room in sdkRooms {
            var summary = RoomSummary(id: room.id(), name: room.displayName() ?? room.id(), isDirect: await room.isDirect())
            if let info = try? await room.roomInfo() {
                summary.isDirect = info.isDirect
                summary.unreadMessages = Int(info.numUnreadMessages)
                summary.sdkMentions = Int(info.numUnreadMentions)
                summary.isMarkedUnread = info.isMarkedUnread
            }
            summary.serverMentions = serverMentions[summary.id] ?? 0
            if case let .remote(timestamp, sender, _, profile, content) = await room.latestEvent() {
                summary.lastActivity = timestamp
                if case let .ready(displayName, _, _, _, _) = profile { summary.lastSender = displayName }
                summary.lastSender = summary.lastSender ?? MentionsModel.localpart(sender)
                if case let .msgLike(like) = content, case let .message(message) = like.kind {
                    summary.lastLine = message.body.split(separator: "\n").first.map(String.init)
                }
            }
            summaries.append(summary)
        }
        // Publish only a real change: every publish re-renders the tab bar and wakes @Mentions
        // and the membership check (perf review, 2026-11-16).
        if summaries != rooms { rooms = summaries }
        hasLoaded = true
    }
}

private final class EntriesListener: RoomListEntriesListener, @unchecked Sendable {
    let onChange: ([RoomListEntriesUpdate]) -> Void
    init(_ onChange: @escaping ([RoomListEntriesUpdate]) -> Void) { self.onChange = onChange }
    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) { onChange(roomEntriesUpdate) }
}
