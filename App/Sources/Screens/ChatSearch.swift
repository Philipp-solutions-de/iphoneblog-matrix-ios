import OSLog
import SwiftUI

/// Search in #one-Chat with Matrix's own server-side search (POST /_matrix/client/v3/search,
/// room_events, filtered to the channel). Our rooms are unencrypted, so the server can read
/// them; there is no index of our own. Synapse stems in English only (its source hard-codes
/// it), so German words match as typed and inflections may not: the empty state says so.
@MainActor
final class ChatSearchModel: ObservableObject {
    struct Hit: Identifiable, Equatable {
        let id: String
        let roomID: String
        let senderID: String
        var senderName: String
        let body: String
        let date: Date
        /// The thread's root when the hit is a reply in a thread.
        let threadRoot: String?
    }

    @Published private(set) var hits: [Hit] = []
    @Published private(set) var highlights: [String] = []
    @Published private(set) var state: State = .idle
    enum State: Equatable { case idle, searching, done, failed }

    private let session: ChatSession
    /// Every #one room; the scope narrows it to the open room ("this room" chip).
    let allRoomIDs: [String]
    let currentRoomID: String?
    @Published var onlyCurrentRoom = false {
        didSet { if oldValue != onlyCurrentRoom { search(term) } }
    }
    private var roomIDs: [String] {
        if onlyCurrentRoom, let currentRoomID { return [currentRoomID] }
        return allRoomIDs
    }
    private var nextBatch: String?
    private var term = ""
    private var task: Task<Void, Never>?
    private var names: [String: String] = [:]
    private let log = Logger(subsystem: Brand.bundleID, category: "search")

    init(session: ChatSession, roomIDs: [String], current: String? = nil) {
        self.session = session
        allRoomIDs = roomIDs
        currentRoomID = current
    }

    var canLoadMore: Bool { nextBatch != nil && state == .done }

    /// Starts a new search; a term under two letters clears the results.
    func search(_ term: String) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        self.term = term
        nextBatch = nil
        guard term.count >= 2 else {
            hits = []
            state = .idle
            return
        }
        task = Task {
            try? await Task.sleep(for: .milliseconds(300)) // typing
            guard !Task.isCancelled else { return }
            await load(replacing: true)
        }
    }

    func loadMore() {
        guard canLoadMore else { return }
        task = Task { await load(replacing: false) }
    }

    private func load(replacing: Bool) async {
        state = .searching
        struct Body: Encodable {
            struct Categories: Encodable { let room_events: RoomEvents } // swiftlint:disable:this nesting identifier_name
            struct RoomEvents: Encodable { // swiftlint:disable:this nesting
                let search_term: String // swiftlint:disable:this identifier_name
                let filter: Filter
                let order_by = "recent" // swiftlint:disable:this identifier_name
                let keys = ["content.body"]
            }
            struct Filter: Encodable { let rooms: [String] } // swiftlint:disable:this nesting
            let search_categories: Categories // swiftlint:disable:this identifier_name
        }
        let body = Body(search_categories: .init(room_events: .init(search_term: term, filter: .init(rooms: roomIDs))))
        var path = "/_matrix/client/v3/search"
        if let nextBatch, !replacing,
           let encoded = nextBatch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?next_batch=\(encoded)"
        }
        do {
            let data = try await session.api("POST", path, body: JSONEncoder().encode(body))
            let page = try JSONDecoder().decode(SearchResponse.self, from: data).search_categories.room_events
            guard !Task.isCancelled else { return }
            var found: [Hit] = []
            for result in page.results ?? [] {
                let event = result.result
                guard event.type == "m.room.message", let raw = event.content?.body else { continue }
                let text = PushText.plain(body: raw, formattedBody: event.content?.formattedBody)
                let root = event.content?.relates?.rel_type == "m.thread" ? event.content?.relates?.event_id : nil
                found.append(Hit(id: event.event_id, roomID: event.room_id ?? roomIDs.first ?? "",
                                 senderID: event.sender, senderName: await name(of: event.sender),
                                 body: text, date: Date(milliseconds: event.origin_server_ts), threadRoot: root))
            }
            hits = replacing ? found : hits + found
            if let words = page.highlights, !words.isEmpty { highlights = words }
            nextBatch = page.next_batch
            state = .done
        } catch {
            guard !Task.isCancelled else { return }
            log.error("search failed: \(error.localizedDescription, privacy: .public)")
            state = .failed
        }
    }

    private func name(of userID: String) async -> String {
        if let known = names[userID] { return known }
        let name = (try? await session.client.getProfile(userId: userID))?.displayName ?? MentionsModel.localpart(userID)
        names[userID] = name
        return name
    }

    private struct SearchResponse: Decodable { // swiftlint:disable identifier_name nesting
        struct Categories: Decodable { let room_events: RoomEvents }
        struct RoomEvents: Decodable {
            let results: [Result]?
            let highlights: [String]?
            let next_batch: String?
        }
        struct Result: Decodable { let result: Event }
        struct Event: Decodable {
            let event_id: String
            let room_id: String?
            let sender: String
            let type: String
            let origin_server_ts: Int64
            let content: Content?
        }
        struct Content: Decodable {
            let body: String?
            let formattedBody: String?
            let relates: Relation?
            enum CodingKeys: String, CodingKey { case body, formattedBody = "formatted_body", relates = "m.relates_to" }
        }
        struct Relation: Decodable { let rel_type: String?; let event_id: String? }
        let search_categories: Categories
    } // swiftlint:enable identifier_name nesting
}

/// The search screen in #one-Chat: a field at the top, results newest first.
struct ChatSearchView: View {
    @StateObject var model: ChatSearchModel
    @ObservedObject var router: Router
    @State private var term = ""

    var roomName: String?

    var body: some View {
        List {
            if model.currentRoomID != nil, model.allRoomIDs.count > 1 {
                scopeChips
                    .listRowInsets(EdgeInsets(top: 6, leading: Theme.Space.page, bottom: 6, trailing: Theme.Space.page))
                    .listRowSeparator(.hidden)
            }
            ForEach(model.hits) { hit in
                Button { open(hit) } label: {
                    SearchHitRow(hit: hit, terms: highlightTerms)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: Theme.Space.page, bottom: 10, trailing: Theme.Space.page))
                .onAppear { if hit == model.hits.last { model.loadMore() } }
            }
            if model.state == .searching, !model.hits.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: "In #one suchen")
        .onChange(of: term) { _, new in model.search(new) }
        .navigationTitle("Suche")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Alle Räume" or only the open room (variant A: the search looks in every room, a chip
    /// narrows it).
    private var scopeChips: some View {
        HStack(spacing: 8) {
            chip("Alle Räume", selected: !model.onlyCurrentRoom) { model.onlyCurrentRoom = false }
                .accessibilityIdentifier("search.scope.all")
            chip("# " + (roomName ?? "Dieser Raum"), selected: model.onlyCurrentRoom) { model.onlyCurrentRoom = true }
                .accessibilityIdentifier("search.scope.room")
            Spacer()
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : Theme.ink2)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(selected ? Theme.teal : Theme.line.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The server's own highlight words (its stems), and what was typed.
    private var highlightTerms: [String] {
        Array(Set(model.highlights + term.split(separator: " ").map(String.init))).filter { $0.count >= 2 }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hits.isEmpty {
            switch model.state {
            case .searching:
                ProgressView()
            case .done:
                ContentUnavailableView("Keine Treffer", systemImage: "magnifyingglass",
                                       description: Text("Die Suche findet Wörter so, wie sie geschrieben sind. Versuch es mit dem Wortstamm, etwa „Monitor“ statt „Monitorarme“."))
            case .failed:
                ContentUnavailableView("Die Suche ist gerade nicht erreichbar", systemImage: "wifi.exclamationmark")
            case .idle:
                ContentUnavailableView("Nachrichten durchsuchen", systemImage: "magnifyingglass",
                                       description: Text("Auch Antworten in Threads."))
            }
        }
    }

    private func open(_ hit: ChatSearchModel.Hit) {
        if let root = hit.threadRoot {
            router.openThread(roomID: hit.roomID, rootEventID: root)
        } else {
            router.openMessage(roomID: hit.roomID, eventID: hit.id)
        }
    }
}

/// One hit: avatar, name, time, and the message with the search words marked in teal.
struct SearchHitRow: View {
    let hit: ChatSearchModel.Hit
    let terms: [String]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.rowGap) {
            MemberAvatar(userID: hit.senderID, name: hit.senderName, roomID: hit.roomID,
                         size: Theme.Size.chatAvatar)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.senderName).font(Theme.Font.name).foregroundStyle(Theme.ink)
                    Text(MentionRow.shortTime(hit.date)).font(Theme.Font.time).foregroundStyle(Theme.ink3)
                    if hit.threadRoot != nil {
                        Text("· Thread").font(Theme.Font.time).foregroundStyle(Theme.teal)
                    }
                }
                Text(Self.marked(Self.snippet(hit.body, around: terms), terms: terms))
                    .font(.system(size: 15.5))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search-hit")
    }

    /// The part of a long message around the first match.
    static func snippet(_ body: String, around terms: [String], radius: Int = 80) -> String {
        let text = body.replacingOccurrences(of: "\n", with: " ")
        guard text.count > radius * 2,
              let range = terms.lazy.compactMap({ text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }).first else {
            return text
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }

    /// Every occurrence of a search word in teal and semibold.
    static func marked(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        for term in terms {
            var searchStart = result.startIndex
            while searchStart < result.endIndex,
                  let range = result[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                result[range].foregroundColor = Theme.teal
                result[range].font = .system(size: 15.5, weight: .semibold)
                searchStart = range.upperBound
            }
        }
        return result
    }
}

/// A search field like the system's, for screens without a navigation bar.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("mentions-search")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink3) }
                    .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
