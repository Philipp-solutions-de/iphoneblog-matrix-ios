import Foundation
import OSLog

/// Where the Blog tab's web view starts, and which hosts count as the blog.
/// The decision (2026-11-15): the blog's own pages with `app=1`, which drops the site's header,
/// menu, footer and sidebar and puts a "Diskussion" link under each article (WordPress PR #274).
enum BlogWeb {
    /// beta until the chat goes live; then `https://www.iphoneblog.de/?app=1`.
    static let defaultHome = "https://beta.iphoneblog.de/?app=1"

    /// The start page; debug builds may point elsewhere (IPHONEBLOG_BLOG_WEB) for tests and screenshots.
    static var home: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["IPHONEBLOG_BLOG_WEB"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: defaultHome)! // swiftlint:disable:this force_unwrapping
    }

    /// The blog's hosts: these stay in the app, with `app=1`. Everything else opens in Safari.
    static func blogHosts(home: URL = home) -> Set<String> {
        var hosts: Set<String> = ["iphoneblog.de", "www.iphoneblog.de"]
        if let host = home.host()?.lowercased() { hosts.insert(host) }
        return hosts
    }

    /// Sign-in pages a blog page may send the reader through, which must stay in the web view:
    /// beta's staff gate signs in at Authelia on `auth.phso.de` (infra docs/staff-gate.md).
    static let signInHosts: Set<String> = ["auth.phso.de"]

    /// The scheme of the "Diskussion" link: `iphoneblog-chat://diskussion?url=<permalink>`.
    static let discussionScheme = "iphoneblog-chat"
}

/// What the web view does with a navigation. Pure, so the rules are tested without a web view.
enum BlogNavigation: Equatable {
    /// Load it in the web view.
    case allow
    /// A blog page without `app=1`: load this address instead (the same page with the flag).
    case reload(URL)
    /// The "Diskussion" link under an article: open the native thread view for this permalink.
    case discussion(URL)
    /// Somewhere else on the web, mail, phone: hand it to the system (Safari, Mail, …).
    case external(URL)
    /// Nothing to do (a malformed app link).
    case ignore

    static func decide(_ url: URL, mainFrame: Bool, blogHosts: Set<String> = BlogWeb.blogHosts(),
                       signInHosts: Set<String> = BlogWeb.signInHosts) -> BlogNavigation {
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case BlogWeb.discussionScheme:
            return DiscussionLink.permalink(from: url).map(BlogNavigation.discussion) ?? .ignore
        case "http", "https":
            // Embeds (videos, tweets) load inside the page wherever they come from.
            guard mainFrame else { return .allow }
            guard let host = url.host()?.lowercased() else { return .ignore }
            if signInHosts.contains(host) { return .allow }
            guard blogHosts.contains(host) else { return .external(url) }
            return AppFlag.isSet(in: url) ? .allow : .reload(AppFlag.added(to: url))
        case "about", "data", "blob":
            return .allow
        default:
            return .external(url)
        }
    }
}

/// The `app=1` query flag that makes WordPress render the app view.
enum AppFlag {
    static func isSet(in url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains { $0.name == "app" && $0.value == "1" } ?? false
    }

    static func added(to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "app" }
        items.append(URLQueryItem(name: "app", value: "1"))
        components.queryItems = items
        return components.url ?? url
    }
}

/// `iphoneblog-chat://diskussion?url=<rawurlencoded permalink>`.
enum DiscussionLink {
    static func permalink(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == BlogWeb.discussionScheme, url.host()?.lowercased() == "diskussion",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "url" })?.value,
              let permalink = URL(string: value), ["http", "https"].contains(permalink.scheme?.lowercased() ?? ""),
              permalink.host() != nil else { return nil }
        return permalink
    }
}

/// An article's identity across hosts: its path. The permalink under an article carries the host
/// that served it (beta, www); links.json is keyed by the www address (2026-11-14_interfaces.md,
/// "Blog app view" and "Matrix at chat.iphoneblog.de").
enum ArticlePath {
    /// `/2026/11/15/slug/`: decoded, lower case, one trailing slash, no query or fragment.
    static func key(_ url: URL) -> String? {
        var path = url.path(percentEncoded: false).lowercased()
        guard !path.isEmpty, path != "/" else { return nil }
        while path.hasSuffix("//") { path.removeLast() }
        if !path.hasSuffix("/") { path += "/" }
        return path
    }
}

/// links.json: every article thread the bot ever started, permalink → thread root.
struct BlogLinkIndex: Equatable {
    private(set) var roots: [String: String] = [:]

    init(roots byURL: [String: String] = [:]) {
        for (address, root) in byURL {
            if let url = URL(string: address), let key = ArticlePath.key(url) { roots[key] = root }
        }
    }

    init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        self.init(roots: file.links)
    }

    func rootEventID(for permalink: URL) -> String? {
        ArticlePath.key(permalink).flatMap { roots[$0] }
    }

    private struct File: Decodable {
        let links: [String: String]
    }
}

/// Reads links.json from the Matrix host's public Blog files, at most once a minute (the bot
/// rewrites it every minute). Signed in and signed out alike: it needs no account.
@MainActor
final class BlogLinkStore {
    static let shared = BlogLinkStore()

    private let base: URL
    private let session: URLSession
    private var index: BlogLinkIndex?
    private var fetched: Date?
    private let log = Logger(subsystem: Brand.bundleID, category: "blog")

    init(base: URL = GuestBlogFeed.defaultBase, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    /// The thread root for an article, or nil when the bot has not started a thread for it.
    /// Throws when the file cannot be read at all.
    func rootEventID(for permalink: URL) async throws -> String? {
        if let index, let root = index.rootEventID(for: permalink) { return root }
        // A miss in a fresh copy is a real miss; an old copy may predate the article.
        if let fetched, Date.now.timeIntervalSince(fetched) < 60, let index { return index.rootEventID(for: permalink) }
        let (data, response) = try await session.data(from: base.appending(path: "links.json"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let fresh = try BlogLinkIndex(json: data)
        index = fresh
        fetched = .now
        log.debug("links.json: \(fresh.roots.count) articles")
        return fresh.rootEventID(for: permalink)
    }
}

/// What the Blog tab's navigation stack holds. `Router.blogPath` is `[String]`: a thread root
/// (`$…`, from a push or a link into the Blog room) or an article from the web view.
enum BlogRoute: Hashable {
    case thread(rootEventID: String)
    case article(URL)

    private static let articlePrefix = "article:"

    init?(_ value: String) {
        if value.hasPrefix(Self.articlePrefix) {
            guard let url = URL(string: String(value.dropFirst(Self.articlePrefix.count))) else { return nil }
            self = .article(url)
        } else if value.hasPrefix("$") {
            self = .thread(rootEventID: value)
        } else {
            return nil
        }
    }

    var value: String {
        switch self {
        case .thread(let root): root
        case .article(let url): Self.articlePrefix + url.absoluteString
        }
    }
}
