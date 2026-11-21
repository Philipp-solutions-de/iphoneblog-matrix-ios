import Foundation
import OSLog
import SwiftUI

/// One search for the blog and #one (ADR-0010 in the WordPress repository): posts, #one posts,
/// links, video passages, chat messages and the Blog's discussions, ranked against each other by
/// the server. `GET <homeserver>/_iphoneblog/v1/search`, with the app's Matrix token when signed
/// in; the server decides from the token what the reader may see. Anonymous readers get posts,
/// links, discussions and #one posts by their teaser ("Nur für #one").

/// One hit, ready to draw: every string and highlight is built off the main thread when the
/// answer arrives, so a row only lays out text while the list scrolls (docs/performance.md).
struct SiteSearchHit: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case post, one, video, link, chat, discussion
    }

    let id: String
    let kind: Kind
    /// The server's German label: Beitrag, #one, Video, Link, Chat, Diskussion.
    let label: String
    let title: AttributedString
    let snippet: AttributedString
    /// The line under the snippet: who, where, when.
    let meta: String
    let url: URL?
    let deepLink: URL?
    /// For a video: the passage's first second.
    let seconds: Int?
    let roomID: String?
    let eventID: String?
    let threadRoot: String?
    let postID: Int?
    /// A #one post found by someone outside #one: title and teaser only.
    let locked: Bool
}

/// The filter chips over the list. Each names the server's types it shows.
enum SiteSearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all, posts, videos, links, chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Alle"
        case .posts: return "Beiträge"
        case .videos: return "Videos"
        case .links: return "Links"
        case .chat: return "Chat"
        }
    }

    /// Nil: every type the reader may see (the server's default).
    var types: [SiteSearchHit.Kind]? {
        switch self {
        case .all: return nil
        case .posts: return [.post, .one]
        case .videos: return [.video]
        case .links: return [.link]
        // The Blog's discussions are chat too: replies under an article.
        case .chat: return [.chat, .discussion]
        }
    }

    /// The chip's number from the answer's per-type counts.
    func count(in counts: [String: Int]) -> Int {
        guard let types else { return counts.values.reduce(0, +) }
        return types.reduce(0) { $0 + (counts[$1.rawValue] ?? 0) }
    }
}

/// One answer, decoded and prepared.
struct SiteSearchPage: Sendable, Equatable {
    let total: Int
    let counts: [String: Int]
    let hits: [SiteSearchHit]
}

enum SiteSearchError: Error, Equatable {
    /// 429: more than the server allows from one address.
    case rate
    /// 503: Typesense does not answer.
    case down
    case failed
}

// MARK: - The wire format

/// The answer as the server sends it (ADR-0010, "The public API").
struct SiteSearchResponse: Decodable {
    struct Hit: Decodable { // swiftlint:disable identifier_name
        let id: String
        let type: String
        let label: String?
        let title: String?
        let snippet: String?
        let url: String?
        let deep_link: String?
        let t: Int?
        let room_id: String?
        let event_id: String?
        let thread_root: String?
        let room_name: String?
        let sender_name: String?
        let domain: String?
        let post_id: Int?
        let published: String?
        let locked: Bool?
    } // swiftlint:enable identifier_name

    let total: Int
    let counts: [String: Int]?
    let hits: [Hit]
}

// MARK: - Highlights

/// The server's snippet is HTML-escaped text with `<mark>` around the matched words and nothing
/// else (ADR-0010). This turns it into attributed text: the marks teal and semibold, every
/// other tag dropped, the entities decoded. Pure and Sendable, so it runs off the main thread.
enum SearchMarkup {
    static let markFont = Font.system(size: 15.5, weight: .semibold)

    static func attributed(_ html: String, markFont: Font = markFont) -> AttributedString {
        var result = AttributedString()
        var marked = false
        var rest = Substring(html)
        func append(_ raw: Substring) {
            guard !raw.isEmpty else { return }
            var piece = AttributedString(decode(String(raw)))
            if marked {
                piece.foregroundColor = Theme.teal
                piece.font = markFont
            }
            result.append(piece)
        }
        while let open = rest.firstIndex(of: "<") {
            append(rest[..<open])
            guard let close = rest[open...].firstIndex(of: ">") else {
                append(rest[open...])
                rest = ""
                break
            }
            let tag = rest[rest.index(after: open)..<close].lowercased().trimmingCharacters(in: .whitespaces)
            if tag == "mark" { marked = true } else if tag == "/mark" { marked = false }
            rest = rest[rest.index(after: close)...]
        }
        append(rest)
        return result
    }

    /// The text without its marks, for titles and accessibility.
    static func plain(_ html: String) -> String {
        String(attributed(html).characters)
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, value) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
                                ("&#039;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
    }
}

// MARK: - Preparing an answer

extension SiteSearchPage {
    /// Decodes and prepares a page; runs where it is called, so the client calls it off the
    /// main thread.
    static func prepare(_ data: Data) throws -> SiteSearchPage {
        let response = try JSONDecoder().decode(SiteSearchResponse.self, from: data)
        var seen = Set<String>()
        let hits = response.hits.compactMap { hit -> SiteSearchHit? in
            guard let kind = SiteSearchHit.Kind(rawValue: hit.type), seen.insert(hit.id).inserted else { return nil }
            return SiteSearchHit(
                id: hit.id,
                kind: kind,
                label: hit.label ?? kind.fallbackLabel,
                title: SearchMarkup.attributed(hit.title ?? "", markFont: .system(size: 16, weight: .bold)),
                snippet: SearchMarkup.attributed(hit.snippet ?? ""),
                meta: meta(hit, kind: kind),
                url: hit.url.flatMap(URL.init(string:)),
                deepLink: hit.deep_link.flatMap(URL.init(string:)),
                seconds: hit.t,
                roomID: hit.room_id,
                eventID: hit.event_id,
                threadRoot: hit.thread_root,
                postID: hit.post_id,
                locked: hit.locked ?? false)
        }
        return SiteSearchPage(total: response.total, counts: response.counts ?? [:], hits: hits)
    }

    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "de_DE"))

    /// "Jana · #one-chat · 17. Nov. 2026", "apple.com · in 4 Beiträgen", "ab 12:34 · 15. Okt. 2026".
    static func meta(_ hit: SiteSearchResponse.Hit, kind: SiteSearchHit.Kind) -> String {
        var parts: [String] = []
        switch kind {
        case .chat:
            if let name = hit.sender_name, !name.isEmpty { parts.append(name) }
            if let room = hit.room_name, !room.isEmpty { parts.append("# " + room) }
        case .discussion:
            if let name = hit.sender_name, !name.isEmpty { parts.append(name) }
        case .link:
            if let domain = hit.domain, !domain.isEmpty { parts.append(domain) }
        case .video:
            if let seconds = hit.t { parts.append("ab " + Episode.duration(Double(seconds))) }
        case .post, .one:
            break
        }
        if let raw = hit.published, let date = try? Date(raw, strategy: .iso8601) {
            parts.append(date.formatted(dateStyle))
        }
        return parts.joined(separator: " · ")
    }
}

extension SiteSearchHit.Kind {
    var fallbackLabel: String {
        switch self {
        case .post: return "Beitrag"
        case .one: return "#one"
        case .video: return "Video"
        case .link: return "Link"
        case .chat: return "Chat"
        case .discussion: return "Diskussion"
        }
    }
}

// MARK: - The client

/// One request to the search API. A token the server refuses (401) is refreshed once; refused
/// again, the search goes out without it, as an anonymous reader's (ADR-0010: "send none to
/// search as anonymous").
struct SiteSearchClient: Sendable {
    let endpoint: URL
    /// The Matrix access token, nil when signed out.
    let token: @Sendable () async -> String?
    /// Makes the SDK refresh an expired token.
    let refresh: @Sendable () async -> Void
    var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await SiteSearchClient.session.data(for: $0) }

    static let limit = 20
    /// The server serves at most five pages (page × limit ≤ 100).
    static let maxPage = 5

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// `<homeserver>/_iphoneblog/v1/search`; a debug run may point it at a fixture
    /// (IPHONEBLOG_SEARCH_URL).
    static var defaultEndpoint: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["IPHONEBLOG_SEARCH_URL"], let url = URL(string: override) {
            return url
        }
        #endif
        let base = MatrixClientFactory.homeserverURL().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/_iphoneblog/v1/search")! // swiftlint:disable:this force_unwrapping
    }

    static let anonymous = SiteSearchClient(endpoint: defaultEndpoint, token: { nil }, refresh: { })

    func request(query: String, types: [SiteSearchHit.Kind]?, page: Int, token: String?) -> URLRequest? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        var items = [URLQueryItem(name: "q", value: String(query.prefix(200))),
                     URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "limit", value: String(Self.limit))]
        if let types { items.append(URLQueryItem(name: "types", value: types.map(\.rawValue).joined(separator: ","))) }
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    func search(_ query: String, types: [SiteSearchHit.Kind]?, page: Int) async throws -> SiteSearchPage {
        var token = await token()
        for attempt in 0..<3 {
            guard let request = request(query: query, types: types, page: page, token: token) else { throw SiteSearchError.failed }
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200:
                return try Self.prepareOffMain(data)
            case 401 where token != nil:
                if attempt == 0 {
                    await refresh()
                    token = await self.token()
                } else {
                    token = nil
                }
            case 429: throw SiteSearchError.rate
            case 503: throw SiteSearchError.down
            default: throw SiteSearchError.failed
            }
        }
        throw SiteSearchError.failed
    }

    /// Not on the main actor: decoding and building the highlights of 20 hits is the one piece of
    /// work per answer worth a frame.
    private static func prepareOffMain(_ data: Data) throws -> SiteSearchPage {
        assert(!Thread.isMainThread, "search answers are prepared off the main thread")
        do { return try SiteSearchPage.prepare(data) } catch { throw SiteSearchError.failed }
    }
}

// MARK: - The model

/// The search screen's state: the query, the chip, the hits. One per app (AppModel), so the
/// search shows what it showed when it opens again after a hit was opened.
@MainActor
final class SiteSearchModel: ObservableObject {
    enum State: Equatable { case idle, searching, done, failed(SiteSearchError) }

    /// The pause after the last keystroke before a request goes out (ADR-0010, "Speed").
    static let typingPause: Duration = .milliseconds(120)
    static let minimumLength = 2

    @Published var query = "" {
        didSet { if oldValue != query { schedule(pause: true) } }
    }
    @Published var filter: SiteSearchFilter = .all {
        didSet { if oldValue != filter { schedule(pause: false) } }
    }
    @Published private(set) var hits: [SiteSearchHit] = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var state: State = .idle
    @Published private(set) var loadingMore = false
    /// Whether the reader is signed in: the empty screen says what the search covers.
    @Published private(set) var signedIn = false

    private(set) var client: SiteSearchClient
    private var total = 0
    private var page = 1
    private var task: Task<Void, Never>?
    private var moreTask: Task<Void, Never>?
    /// Counts every new search; an answer to an older one is dropped.
    private var generation = 0
    private let log = Logger(subsystem: Brand.bundleID, category: "site-search")

    init(client: SiteSearchClient = .anonymous) {
        self.client = client
    }

    /// Signed in or out: what the reader may see changes, so the hits go.
    func setAccount(token: (@Sendable () async -> String?)?, refresh: @escaping @Sendable () async -> Void) {
        client = SiteSearchClient(endpoint: client.endpoint, token: token ?? { nil }, refresh: refresh, transport: client.transport)
        signedIn = token != nil
        if !trimmed.isEmpty { schedule(pause: false) }
    }

    /// For tests: another transport.
    func setTransport(_ transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        client.transport = transport
    }

    var canLoadMore: Bool { state == .done && hits.count < total && page < SiteSearchClient.maxPage && !loadingMore }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A new search: the older one is cancelled (its request too) and its answer dropped.
    private func schedule(pause: Bool) {
        task?.cancel()
        moreTask?.cancel()
        loadingMore = false
        generation += 1
        let term = trimmed
        guard term.count >= Self.minimumLength else {
            hits = []
            counts = [:]
            total = 0
            state = .idle
            return
        }
        state = .searching
        let generation = generation, types = filter.types, client = client
        task = Task { [weak self] in
            if pause {
                do { try await Task.sleep(for: Self.typingPause) } catch { return }
            }
            let result: Result<SiteSearchPage, Error>
            do { result = .success(try await client.search(term, types: types, page: 1)) } catch { result = .failure(error) }
            self?.finish(result, generation: generation, page: 1)
        }
    }

    func loadMore() {
        guard canLoadMore else { return }
        loadingMore = true
        let generation = generation, types = filter.types, client = client, term = trimmed, next = page + 1
        moreTask = Task { [weak self] in
            let result: Result<SiteSearchPage, Error>
            do { result = .success(try await client.search(term, types: types, page: next)) } catch { result = .failure(error) }
            self?.finish(result, generation: generation, page: next)
        }
    }

    private func finish(_ result: Result<SiteSearchPage, Error>, generation: Int, page: Int) {
        guard generation == self.generation else { return }
        if page > 1 { loadingMore = false }
        switch result {
        case .success(let answer):
            self.page = page
            total = answer.total
            counts = answer.counts
            if page == 1 {
                hits = answer.hits
            } else {
                let known = Set(hits.map(\.id))
                hits += answer.hits.filter { !known.contains($0.id) }
            }
            state = .done
        case .failure(let error):
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            log.error("search failed: \(String(describing: error), privacy: .public)")
            if page == 1 {
                hits = []
                state = .failed(error as? SiteSearchError ?? .failed)
            }
        }
    }
}
