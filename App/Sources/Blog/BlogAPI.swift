import Foundation

/// The public JSON the article bot writes on the Matrix host, read without an account
/// (2026-11-14_interfaces.md, "Matrix Blog feed" and "Matrix at chat.iphoneblog.de").
enum GuestAPI {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// links.json: every article thread ever posted, by the article's URL.
    struct Links: Decodable {
        let links: [String: String]
    }

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

    }

    /// A reply in a thread file, oldest first.
    struct Reply: Decodable {
        let eventId: String
        let ts: Int64
        let senderName: String
        let body: String

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


/// Finds and reads an article's discussion: the article URL's PATH leads through links.json to
/// the thread's root event, the thread file holds the title, the count and the replies.
/// Signed in or not, the header comes from here; signed in, the replies come from Matrix.
@MainActor
final class DiscussionStore {
    static let shared = DiscussionStore()

    private var byPath: [String: String] = [:]
    private var loadedAt: Date?
    private let base: URL
    private let session: URLSession

    init(base: URL = DiscussionStore.defaultBase, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    /// The API; debug builds may point elsewhere for screenshots and tests.
    nonisolated static var defaultBase: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["IPHONEBLOG_BLOG_API"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: Brand.blogAPIURL)! // swiftlint:disable:this force_unwrapping
    }

    /// The path an article is matched by: the permalink's decoded path, lower case, with one
    /// trailing slash. Host, query (app=1) and fragment do not count; beta and www lead to the
    /// same thread.
    nonisolated static func key(for url: URL) -> String {
        var path = url.path(percentEncoded: false).lowercased()
        if path.isEmpty { path = "/" }
        while path.hasSuffix("//") { path.removeLast() }
        if !path.hasSuffix("/") { path += "/" }
        return path
    }

    /// The thread's root event for an article, or nil when it has no discussion. Throws when
    /// links.json cannot be read and no copy is at hand. A miss in a copy older than a minute
    /// reads the file again: the article may be newer than the copy.
    func rootEventID(for articleURL: URL) async throws -> String? {
        let key = Self.key(for: articleURL)
        if let root = byPath[key] { return root }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return nil }
        try await loadLinks()
        return byPath[key]
    }

    private func loadLinks() async throws {
        let (data, response) = try await session.data(from: base.appending(path: "links.json"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let links = try GuestAPI.decoder.decode(GuestAPI.Links.self, from: data)
        byPath = Self.index(links)
        loadedAt = Date()
    }

    /// links.json → path key → root event.
    nonisolated static func index(_ links: GuestAPI.Links) -> [String: String] {
        var map: [String: String] = [:]
        for (article, root) in links.links {
            if let url = URL(string: article) { map[key(for: url)] = root }
        }
        return map
    }

    /// The thread file: title, link, count and the newest replies, oldest first.
    func thread(_ rootEventID: String) async throws -> GuestAPI.ThreadPage {
        // appending(path:) encodes the event ID's "$" as %24.
        let url = base.appending(path: "threads").appending(path: "\(rootEventID).json")
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.fileDoesNotExist) }
        return try GuestAPI.decoder.decode(GuestAPI.ThreadPage.self, from: data)
    }
}
