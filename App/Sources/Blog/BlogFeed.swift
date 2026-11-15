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
        return BlogArticle(id: eventID, title: title.isEmpty ? (link?.absoluteString ?? "Artikel") : title,
                           link: link, imageURL: nil, imageSource: nil, date: date,
                           replyCount: replies, latestReply: latest)
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

    init(base: URL = URL(string: Brand.blogAPIURL)!, session: URLSession = .shared) { // swiftlint:disable:this force_unwrapping
        self.base = base
        self.session = session
    }

    func load() async {
        next = nil
        await fetch(replacing: true)
    }

    func loadMore() async {
        guard next != nil else { return }
        await fetch(replacing: false)
    }

    private func fetch(replacing: Bool) async {
        var components = URLComponents(url: base.appending(path: "threads"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "20")] + (next.map { [URLQueryItem(name: "from", value: $0)] } ?? [])
        guard let url = components?.url else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = articles.isEmpty ? .unavailable("Die Artikel sind gerade nicht erreichbar.") : .ready
                return
            }
            let page = try GuestAPI.decoder.decode(GuestAPI.ThreadsPage.self, from: data)
            let new = page.threads.map(\.article)
            articles = replacing ? new : articles + new
            next = page.next
            state = .ready
        } catch {
            log.error("blog feed failed: \(error.localizedDescription, privacy: .public)")
            state = articles.isEmpty ? .unavailable("Die Artikel sind gerade nicht erreichbar.") : .ready
        }
    }

    /// One article thread with its replies, for the signed-out thread screen.
    func thread(_ rootEventID: String) async throws -> (BlogArticle, [BlogReply]) {
        let url = base.appending(path: "threads").appending(path: rootEventID).appending(queryItems: [URLQueryItem(name: "limit", value: "100")])
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

    struct Thread: Decodable {
        let rootEventId: String
        let ts: Int64
        let title: String
        let imageUrl: String?
        let link: String?
        let replyCount: Int
        let latestReplyTs: Int64?

        var article: BlogArticle {
            BlogArticle(id: rootEventId, title: title, link: link.flatMap(URL.init(string:)),
                        imageURL: imageUrl.flatMap(URL.init(string:)), imageSource: nil,
                        date: Date(milliseconds: ts), replyCount: replyCount,
                        latestReply: latestReplyTs.map(Date.init(milliseconds:)))
        }
    }

    struct Reply: Decodable {
        let eventId: String
        let ts: Int64
        let senderName: String
        let senderAvatarUrl: String?
        let body: String

        var reply: BlogReply {
            BlogReply(id: eventId, sender: senderName, avatarURL: senderAvatarUrl.flatMap(URL.init(string:)),
                      body: body, date: Date(milliseconds: ts))
        }
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
    private let service: ThreadListService
    private var items: [ThreadListItem] = []
    private var handle: TaskHandle?
    private var consumer: Task<Void, Never>?

    init(room: Room) {
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
        articles = items.map(Self.article)
            .sorted { ($0.latestReply ?? $0.date) > ($1.latestReply ?? $1.date) }
        if state == .loading, !articles.isEmpty { state = .ready }
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
        return article
    }
}

private final class ThreadListener: ThreadListEntriesListener, @unchecked Sendable {
    let onChange: ([ThreadListUpdate]) -> Void
    init(_ onChange: @escaping ([ThreadListUpdate]) -> Void) { self.onChange = onChange }
    func onUpdate(diff: [ThreadListUpdate]) { onChange(diff) }
}
