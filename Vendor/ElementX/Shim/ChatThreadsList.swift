//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// The Threads tab: every thread you take part in, across all channels, newest activity first,
// unread ones marked; a tap opens the thread (design proposal, "Threads"). Element X has a
// thread list per room only, so this one is ours: the SDK's per-room ThreadListService gives
// the threads and keeps them live, and the server's thread API (`include=participated`)
// says which of them you wrote in.

import Combine
import MatrixRustSDK
import SwiftUI

// MARK: - Model

struct ChatThreadEntry: Identifiable, Equatable {
    var id: String { "\(roomID)|\(rootEventID)" }
    let roomID: String
    let roomName: String
    let isDirect: Bool
    let rootEventID: String
    let rootSender: TimelineItemSender
    let rootText: String
    let replies: Int
    let latestSender: TimelineItemSender?
    let latestText: String?
    let latestIsOwn: Bool
    /// The newest message in the thread, root or reply.
    let lastActivity: Date
}

@MainActor
final class ChatThreadsListModel: ObservableObject {
    @Published private(set) var entries: [ChatThreadEntry] = []
    @Published private(set) var hasLoaded = false

    private let client: Client
    private let ownUserID: String
    private var services: [String: (service: ThreadListService, handle: TaskHandle)] = [:]
    private var itemsByRoom: [String: [ThreadListItem]] = [:]
    private var roomInfo: [String: (name: String, isDirect: Bool)] = [:]
    /// Root event IDs of threads you wrote in, per room, from the server.
    private var participated: [String: Set<String>] = [:]

    init(client: Client, ownUserID: String) {
        self.client = client
        self.ownUserID = ownUserID
    }

    deinit {
        for entry in services.values { entry.handle.cancel() }
    }

    /// Loads the threads of every joined room and keeps them live. Safe to call again.
    func start() async {
        let rooms = client.rooms().filter { $0.membership() == .joined }
        for room in rooms {
            let roomID = room.id()
            roomInfo[roomID] = (room.displayName() ?? roomID, await room.isDirect())
            if services[roomID] == nil {
                let service = room.threadListService()
                let handle = service.subscribeToItemsUpdates(listener: ThreadItemsListener { [weak self] in
                    Task { @MainActor in self?.reload(roomID: roomID) }
                })
                services[roomID] = (service, handle)
                Task { try? await service.paginate() }
            }
            Task { await self.loadParticipated(roomID: roomID) }
        }
        hasLoaded = true
        rebuild()
    }

    /// The server's list of threads you took part in for one room (MSC3856, Matrix 1.4).
    private func loadParticipated(roomID: String) async {
        guard let session = try? client.session(),
              let encoded = roomID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "!:"))),
              let url = URL(string: "\(client.homeserver().trimmingCharacters(in: CharacterSet(charactersIn: "/")))/_matrix/client/v1/rooms/\(encoded)/threads?include=participated&limit=100") else {
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let body: ThreadsResponse
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                MXLog.error("Threads list: \(url.path) answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            body = try JSONDecoder().decode(ThreadsResponse.self, from: data)
        } catch {
            MXLog.error("Threads list: \(url.absoluteString) failed: \(error)")
            return
        }
        participated[roomID] = Set(body.chunk.map(\.event_id))
        rebuild()
    }

    private func reload(roomID: String) {
        itemsByRoom[roomID] = services[roomID]?.service.items() ?? []
        rebuild()
    }

    private func rebuild() {
        var result: [ChatThreadEntry] = []
        for (roomID, items) in itemsByRoom {
            let info = roomInfo[roomID] ?? (roomID, false)
            let mine = participated[roomID] ?? []
            for item in items {
                let root = item.rootEvent
                // Yours if you started it, wrote the latest reply, or the server says you wrote in it.
                guard root.isOwn || item.latestEvent?.isOwn == true || mine.contains(root.eventId) else { continue }
                let latest = item.latestEvent
                result.append(ChatThreadEntry(roomID: roomID,
                                              roomName: info.name,
                                              isDirect: info.isDirect,
                                              rootEventID: root.eventId,
                                              rootSender: Self.sender(root),
                                              rootText: Self.text(root.content),
                                              replies: Int(item.numReplies),
                                              latestSender: latest.map(Self.sender),
                                              latestText: latest.map { Self.text($0.content) },
                                              latestIsOwn: latest?.isOwn ?? root.isOwn,
                                              lastActivity: Self.date(latest?.timestamp ?? root.timestamp)))
            }
        }
        entries = result.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: Helpers

    private static func sender(_ event: ThreadListItemEvent) -> TimelineItemSender {
        TimelineItemSender(senderID: event.sender, senderProfile: event.senderProfile)
    }

    private static func text(_ content: TimelineItemContent?) -> String {
        guard case let .msgLike(content)? = content else { return "" }
        switch content.kind {
        case .message(let message): return message.body
        case .sticker(let body, _, _): return body
        case .poll(let question, _, _, _, _, _, _): return question
        default: return ""
        }
    }

    private static func date(_ timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

    private struct ThreadsResponse: Decodable {
        struct Event: Decodable { let event_id: String } // swiftlint:disable:this identifier_name
        let chunk: [Event]
    }
}

private final class ThreadItemsListener: ThreadListEntriesListener, @unchecked Sendable {
    let onChange: () -> Void
    init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    func onUpdate(diff: [ThreadListUpdate]) { onChange() }
}

// MARK: - Seen on this device

/// When you last opened each thread, kept on this device. A thread with a newer reply from
/// someone else counts as unread.
enum ChatThreadSeen {
    private static let key = "chatkit.threadSeen"

    static func markSeen(roomID: String, rootEventID: String, at date: Date = .now) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        all["\(roomID)|\(rootEventID)"] = date.timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: key)
    }

    static func isUnread(_ entry: ChatThreadEntry) -> Bool {
        guard !entry.latestIsOwn else { return false }
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        guard let seen = all[entry.id] else { return true }
        return entry.lastActivity.timeIntervalSince1970 > seen
    }
}

// MARK: - View

struct ChatThreadsListView: View {
    @StateObject var model: ChatThreadsListModel
    let mediaProvider: MediaProviderProtocol?
    let open: (ChatThreadEntry) -> Void

    private var style: ChatKitStyle { ChatKitStyle.current }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.entries) { entry in
                    Button {
                        ChatThreadSeen.markSeen(roomID: entry.roomID, rootEventID: entry.rootEventID)
                        open(entry)
                    } label: {
                        ChatThreadRow(entry: entry, isUnread: ChatThreadSeen.isUnread(entry), mediaProvider: mediaProvider)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(style.colors.line).frame(height: 1)
                        .padding(.leading, style.metrics.page + style.metrics.avatar + style.metrics.avatarGap)
                }
            }
        }
        .background(style.colors.background)
        .overlay {
            if !model.hasLoaded {
                ProgressView()
            } else if model.entries.isEmpty {
                ContentUnavailableView(ChatKitStrings.noThreadsTitle, systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text(ChatKitStrings.noThreadsText))
            }
        }
        .task { await model.start() }
    }
}

/// One thread: where it is, who started it with what, how many replies and who wrote last.
struct ChatThreadRow: View {
    let entry: ChatThreadEntry
    let isUnread: Bool
    let mediaProvider: MediaProviderProtocol?

    private var style: ChatKitStyle { ChatKitStyle.current }

    var body: some View {
        HStack(alignment: .top, spacing: style.metrics.avatarGap) {
            ChatAvatar(sender: entry.rootSender, size: style.metrics.avatar, mediaProvider: mediaProvider)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.isDirect ? entry.roomName : "# \(entry.roomName)")
                        .font(style.fonts.time.weight(.semibold))
                        .foregroundStyle(style.colors.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.lastActivity.formatted(.relative(presentation: .named)))
                        .font(style.fonts.time)
                        .foregroundStyle(style.colors.ink3)
                    if isUnread {
                        Circle().fill(style.colors.highlight).frame(width: 9, height: 9)
                    }
                }
                Text(entry.rootSender.displayName ?? entry.rootSender.id)
                    .font(style.fonts.senderName)
                    .foregroundStyle(style.colors.ink)
                Text(entry.rootText)
                    .foregroundStyle(style.colors.ink)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(ChatKitStrings.replies(entry.replies))
                        .font(style.fonts.threadSummary)
                        .foregroundStyle(style.colors.accent)
                    if let latest = entry.latestSender, let text = entry.latestText {
                        Text("· \(latest.displayName ?? latest.id): \(text)")
                            .font(style.fonts.threadPreview)
                            .foregroundStyle(style.colors.ink3)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, style.metrics.page)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isUnread ? [.isButton, .updatesFrequently] : .isButton)
    }
}
