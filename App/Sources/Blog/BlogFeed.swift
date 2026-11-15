import Foundation
import MatrixRustSDK
import OSLog

/// One article in the Blog tab: the bot's post that starts the thread, and its replies' count.
struct BlogArticle: Identifiable, Hashable {
    /// The thread root's event ID.
    let id: String
    var title: String
    var link: URL?
    /// An https address (signed out) or nothing; signed in, `imageSource` carries the image.
    var imageURL: URL?
    var imageSource: MediaSourceBox?
    var date: Date
    var replyCount: Int
    var latestReply: Date?
    /// Two lines under the title.
    var teaser: String?
    /// The last people who replied, newest first (names; avatars where the source has them).
    var repliers: [Replier] = []

    struct Replier: Hashable {
        var name: String
        var avatarURL: URL?
    }

    /// Reads the bot's post: the first line without a web address is the title, the first web
    /// address is the article. An image post carries its picture.
    static func parse(body: String, eventID: String, date: Date, replies: Int, latest: Date?) -> BlogArticle {
        let lines = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let link = lines.lazy.compactMap { line -> URL? in
            guard let range = line.range(of: #"https?://\S+"#, options: .regularExpression) else { return nil }
            return URL(string: String(line[range]))
        }.first
        let title = lines.first { !$0.isEmpty && $0.range(of: #"^https?://"#, options: .regularExpression) == nil }
            .map { $0.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) } ?? body
        // Everything after the title line that is not just a web address is the teaser.
        let titleIndex = lines.firstIndex { !$0.isEmpty && $0.range(of: #"^https?://"#, options: .regularExpression) == nil }
        let after: [String] = titleIndex.map { Array(lines[($0 + 1)...]) } ?? []
        let rest = after.filter { !$0.isEmpty && $0.range(of: #"^https?://\S+$"#, options: .regularExpression) == nil }
        return BlogArticle(id: eventID, title: title.isEmpty ? (link?.absoluteString ?? "Artikel") : title,
                           link: link, imageURL: nil, imageSource: nil, date: date,
                           replyCount: replies, latestReply: latest,
                           teaser: rest.isEmpty ? nil : rest.joined(separator: " "))
    }
}

/// `MediaSource` is a class from the SDK; wrapped so `BlogArticle` stays Hashable.
struct MediaSourceBox: Hashable {
    let source: MediaSource
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.source.url() == rhs.source.url() }
    func hash(into hasher: inout Hasher) { hasher.combine(source.url()) }
}

/// A reply inside an article thread, for signed-out reading.
struct BlogReply: Identifiable, Hashable {
    let id: String
    var sender: String
    var avatarURL: URL?
    var body: String
    var date: Date
}

/// The Blog tab's data, signed in or not.
@MainActor
protocol BlogFeed: AnyObject {
    var articles: [BlogArticle] { get }
    var state: BlogFeedState { get }
    func load() async
    func loadMore() async
}

enum BlogFeedState: Equatable {
    case loading
    case ready
    /// Nothing to show and why, in words for the reader.
    case unavailable(String)
}

// MARK: - Signed out: the read-only JSON API

/// Reads the Blog room without an account, through the Matrix host's read-only API
/// (2026-11-14_interfaces.md, "Blog for signed-out readers").
@MainActor
final class GuestBlogFeed: ObservableObject, BlogFeed {
    @Published private(set) var articles: [BlogArticle] = []
    @Published private(set) var state: BlogFeedState = .loading
    private var next: String?
    private let base: URL
    private let session: URLSession
    private let log = Logger(subsystem: Brand.bundleID, category: "blog")

    init(base: URL = GuestBlogFeed.defaultBase, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    /// The read-only API; debug builds may point elsewhere for screenshots and tests.
    nonisolated static var defaultBase: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["IPHONEBLOG_BLOG_API"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: Brand.blogAPIURL)! // swiftlint:disable:this force_unwrapping
    }

    func load() async {
        next = nil
        await fetch(replacing: true)
    }

    func loadMore() async {
        guard next != nil else { return }
        await fetch(replacing: false)
    }

    /// The static index the bot rewrites every minute: the newest 100 threads, no paging
    /// (2026-11-14_interfaces.md, "Matrix Blog feed").
    private func fetch(replacing: Bool) async {
        let url = base.appending(path: "threads.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = articles.isEmpty ? .unavailable("Die Artikel sind gerade nicht erreichbar.") : .ready
                return
            }
            let page = try GuestAPI.decoder.decode(GuestAPI.ThreadsPage.self, from: data)
            articles = page.threads.map(\.article)
            next = nil
            state = .ready
        } catch {
            log.error("blog feed failed: \(error.localizedDescription, privacy: .public)")
            state = articles.isEmpty ? .unavailable("Die Artikel sind gerade nicht erreichbar.") : .ready
        }
    }

    /// One article thread with its replies, for the signed-out thread screen.
    func thread(_ rootEventID: String) async throws -> (BlogArticle, [BlogReply]) {
        // One static file per thread; appending(path:) encodes the event ID's "$" as %24.
        let url = base.appending(path: "threads").appending(path: "\(rootEventID).json")
        let (data, _) = try await session.data(from: url)
        let page = try GuestAPI.decoder.decode(GuestAPI.ThreadPage.self, from: data)
        return (page.root.article, page.replies.map(\.reply))
    }
}

/// The JSON the read-only API answers with.
enum GuestAPI {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    struct ThreadsPage: Decodable {
        let threads: [Thread]
        let next: String?
    }

    struct ThreadPage: Decodable {
        let root: Thread
        let replies: [Reply]
        let next: String?
    }

    /// One article thread, as in threads.json.
    struct Thread: Decodable {
        let rootEventId: String
        let title: String
        let link: String?
        let imageUrl: String?
        let teaser: String?
        let publishedTs: Int64
        let replyCount: Int
        let latestReplyTs: Int64?
        let lastRepliers: [Replier]?

        /// Names only: the server shows no avatars (Synapse's media needs a token).
        struct Replier: Decodable {
            let name: String
        }

        var article: BlogArticle {
            BlogArticle(id: rootEventId, title: title, link: link.flatMap(URL.init(string:)),
                        imageURL: imageUrl.flatMap(URL.init(string:)), imageSource: nil,
                        date: Date(milliseconds: publishedTs), replyCount: replyCount,
                        latestReply: latestReplyTs.map(Date.init(milliseconds:)),
                        teaser: teaser,
                        repliers: (lastRepliers ?? []).map { .init(name: $0.name, avatarURL: nil) })
        }
    }

    /// A reply in a thread file, oldest first.
    struct Reply: Decodable {
        let eventId: String
        let ts: Int64
        let senderName: String
        let body: String

        var reply: BlogReply {
            BlogReply(id: eventId, sender: senderName, avatarURL: nil, body: body, date: Date(milliseconds: ts))
        }
    }

    /// The bot's field on every article root event: `de.iphoneblog.article`.
    struct ArticleField: Decodable {
        let title: String?
        let link: String?
        let teaser: String?
        let imageUrl: String?
        let publishedTs: Int64?
    }
}

extension Date {
    init(milliseconds: Int64) { self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1000) }
}

// MARK: - Signed in: the Blog room's threads through the SDK

/// Reads the Blog room's threads with the SDK's thread list, newest activity first.
@MainActor
final class MatrixBlogFeed: ObservableObject, BlogFeed {
    @Published private(set) var articles: [BlogArticle] = []
    @Published private(set) var state: BlogFeedState = .loading

    let roomID: String
    private let room: Room
    private let service: ThreadListService
    private var items: [ThreadListItem] = []
    /// The bot's article field per root event, read once from the event's JSON.
    private var fields: [String: GuestAPI.ArticleField] = [:]
    private var reading: Set<String> = []
    private let client: Client?
    private var handle: TaskHandle?
    private var consumer: Task<Void, Never>?

    init(room: Room, client: Client? = nil) {
        self.room = room
        self.client = client
        roomID = room.id()
        service = room.threadListService()
        let (stream, continuation) = AsyncStream.makeStream(of: [ThreadListUpdate].self)
        consumer = Task { [weak self] in
            for await diff in stream { self?.apply(diff) }
        }
        handle = service.subscribeToItemsUpdates(listener: ThreadListener { continuation.yield($0) })
    }

    func load() async {
        await service.reset()
        do {
            try await service.paginate()
            state = .ready
        } catch {
            state = articles.isEmpty ? .unavailable("Die Artikel sind gerade nicht erreichbar.") : .ready
        }
    }

    func loadMore() async {
        try? await service.paginate()
    }

    private func apply(_ diff: [ThreadListUpdate]) {
        for update in diff {
            switch update {
            case .append(let values): items.append(contentsOf: values)
            case .clear: items.removeAll()
            case .pushFront(let value): items.insert(value, at: 0)
            case .pushBack(let value): items.append(value)
            case .popFront: if !items.isEmpty { items.removeFirst() }
            case .popBack: if !items.isEmpty { items.removeLast() }
            case .insert(let index, let value): items.insert(value, at: min(Int(index), items.count))
            case .set(let index, let value): if Int(index) < items.count { items[Int(index)] = value }
            case .remove(let index): if Int(index) < items.count { items.remove(at: Int(index)) }
            case .truncate(let length): items = Array(items.prefix(Int(length)))
            case .reset(let values): items = values
            }
        }
        rebuild()
        if state == .loading, !articles.isEmpty { state = .ready }
        Task { await readFields() }
    }

    private func rebuild() {
        articles = items.map { item in
            var article = Self.article(item)
            if let field = fields[article.id] { Self.merge(field, into: &article) }
            return article
        }
        .sorted { ($0.latestReply ?? $0.date) > ($1.latestReply ?? $1.date) }
    }

    /// The SDK's thread list carries the root's text, not its custom fields, and its timeline
    /// only knows events it has loaded. So the root event comes from the client API
    /// (GET /rooms/{room}/event/{event}) with the session's current token; the bot's field holds
    /// title, teaser, image and link. Read once per article.
    private func readFields() async {
        let missing = items.map(\.rootEvent.eventId).filter { fields[$0] == nil && !reading.contains($0) }
        guard !missing.isEmpty, let client else { return }
        reading.formUnion(missing)
        for eventID in missing {
            guard let session = try? client.session(),
                  let url = URL(string: session.homeserverUrl)?
                    .appending(path: "_matrix/client/v3/rooms").appending(path: roomID)
                    .appending(path: "event").appending(path: eventID) else { continue }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let field = Self.articleField(fromEventJSON: String(decoding: data, as: UTF8.self)) else {
                reading.remove(eventID)
                continue
            }
            fields[eventID] = field
        }
        rebuild()
    }

    /// `content["de.iphoneblog.article"]` of a raw event, or nil.
    static func articleField(fromEventJSON json: String) -> GuestAPI.ArticleField? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let content = object["content"] as? [String: Any],
              let field = content["de.iphoneblog.article"],
              let data = try? JSONSerialization.data(withJSONObject: field) else { return nil }
        return try? GuestAPI.decoder.decode(GuestAPI.ArticleField.self, from: data)
    }

    static func merge(_ field: GuestAPI.ArticleField, into article: inout BlogArticle) {
        if let title = field.title, !title.isEmpty { article.title = title }
        if let link = field.link.flatMap(URL.init(string:)) { article.link = link }
        if let teaser = field.teaser, !teaser.isEmpty { article.teaser = teaser }
        if let image = field.imageUrl.flatMap(URL.init(string:)) { article.imageURL = image }
        if let published = field.publishedTs { article.date = Date(milliseconds: published) }
    }

    private static func article(_ item: ThreadListItem) -> BlogArticle {
        let root = item.rootEvent
        var body = ""
        var image: MediaSource?
        if case .msgLike(let content)? = root.content, case .message(let message) = content.kind {
            body = message.body
            if case .image(let picture) = message.msgType {
                image = picture.info?.thumbnailSource ?? picture.source
                body = picture.caption ?? body
            }
        }
        var article = BlogArticle.parse(body: body, eventID: root.eventId,
                                        date: Date(milliseconds: Int64(root.timestamp)),
                                        replies: Int(item.numReplies),
                                        latest: item.latestEvent.map { Date(milliseconds: Int64($0.timestamp)) })
        article.imageSource = image.map(MediaSourceBox.init)
        if item.numReplies > 0, let latest = item.latestEvent {
            if case .ready(let name, _, _, _, _) = latest.senderProfile {
                article.repliers = [.init(name: name ?? latest.sender, avatarURL: nil)]
            } else {
                article.repliers = [.init(name: latest.sender, avatarURL: nil)]
            }
        }
        return article
    }
}

private final class ThreadListener: ThreadListEntriesListener, @unchecked Sendable {
    let onChange: ([ThreadListUpdate]) -> Void
    init(_ onChange: @escaping ([ThreadListUpdate]) -> Void) { self.onChange = onChange }
    func onUpdate(diff: [ThreadListUpdate]) { onChange(diff) }
}
