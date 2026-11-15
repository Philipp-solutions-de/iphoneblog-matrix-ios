import Foundation
import MatrixRustSDK

/// One row in the channel list.
struct RoomSummary: Identifiable, Equatable {
    let id: String
    var name: String
    var isDirect: Bool
    /// Messages since the last read marker.
    var unreadMessages: Int = 0
    /// Mentions of me and keyword hits since the last read marker.
    var unreadMentions: Int = 0
    var isMarkedUnread = false

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
    var channels: [RoomSummary] { rooms.filter { !$0.isDirect && !hidden.contains($0.id) } }
    var directMessages: [RoomSummary] { rooms.filter(\.isDirect) }
    var withMentions: [RoomSummary] { rooms.filter { $0.unreadMentions > 0 && !hidden.contains($0.id) } }
    /// Direct messages count as mentions: they are meant for you.
    var badgeCount: Int { rooms.reduce(0) { $0 + ($1.isDirect ? $1.unreadMessages : $1.unreadMentions) } }

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
                summary.unreadMentions = Int(info.numUnreadMentions)
                summary.isMarkedUnread = info.isMarkedUnread
            }
            summaries.append(summary)
        }
        rooms = summaries
        hasLoaded = true
    }
}

private final class EntriesListener: RoomListEntriesListener, @unchecked Sendable {
    let onChange: ([RoomListEntriesUpdate]) -> Void
    init(_ onChange: @escaping ([RoomListEntriesUpdate]) -> Void) { self.onChange = onChange }
    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) { onChange(roomEntriesUpdate) }
}
