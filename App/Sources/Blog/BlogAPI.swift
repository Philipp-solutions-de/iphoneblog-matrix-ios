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
        /// "m.text", "m.image", …; a picture's or file's body says to see it in the app.
        let msgtype: String?
        /// Sanitized on the server with the website's allowlist (ReplyHTML).
        let formattedBody: String?
        /// A picture, copied by the server to a public address (EXIF stripped, max 800×600).
        let media: Media?
    }

    struct Media: Decodable, Equatable {
        let url: URL
        let w: Int?
        let h: Int?
        let thumbnailUrl: URL?
        let thumbnailW: Int?
        let thumbnailH: Int?
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

    /// The thread's root event for an article. Signed in (`token`), the server makes the thread
    /// if the article has none yet (`POST article-thread`, idempotent per post); signed out, the
    /// app tries the same call without a token and else reads links.json. Nil: no thread, and
    /// none could be made. Throws when neither answers.
    /// 2026-11-14_interfaces.md, "article-thread".
    func rootEventID(for articleURL: URL, token: String?) async throws -> String? {
        let key = Self.key(for: articleURL)
        if let root = byPath[key] { return root }
        do {
            if let root = try await articleThread(articleURL, token: token) {
                byPath[key] = root
                return root
            }
        } catch {
            // Signed in, the server's answer counts; links.json is only the reader's way in.
            if token != nil, (error as? URLError)?.code != .notConnectedToInternet { throw error }
        }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return byPath[key] }
        try await loadLinks()
        return byPath[key]
    }

    /// `POST article-thread`. Nil when the server refuses the call (no token) or knows no such
    /// article; throws on a network or server error.
    private func articleThread(_ articleURL: URL, token: String?) async throws -> String? {
        var request = URLRequest(url: Self.articleThreadURL(base: base))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(["url": Self.canonical(articleURL).absoluteString])
        for attempt in 0..<3 {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                return try GuestAPI.decoder.decode(ArticleThread.self, from: data).rootEventId
            case 401, 403, 404:
                return nil
            case 429, 502, 503:
                guard attempt < 2 else { throw URLError(.badServerResponse) }
                let wait = (try? JSONDecoder().decode(RetryAfter.self, from: data))?.retryAfterMs ?? 1000
                try await Task.sleep(for: .milliseconds(min(wait, 5000)))
            default:
                throw URLError(.badServerResponse)
            }
        }
        throw URLError(.badServerResponse)
    }

    private struct ArticleThread: Decodable { let rootEventId: String }
    private struct RetryAfter: Decodable {
        let retryAfterMs: Int
        enum CodingKeys: String, CodingKey { case retryAfterMs = "retry_after_ms" }
    }

    /// `…/_iphoneblog/v1/blog` → `…/_iphoneblog/v1/article-thread`.
    nonisolated static func articleThreadURL(base: URL) -> URL {
        base.deletingLastPathComponent().appending(path: "article-thread")
    }

    /// The article's own address, as the server wants it: www.iphoneblog.de, no query, no
    /// fragment. The web view may be on beta with app=1.
    nonisolated static func canonical(_ url: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.iphoneblog.de"
        components.path = key(for: url)
        return components.url ?? url
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
