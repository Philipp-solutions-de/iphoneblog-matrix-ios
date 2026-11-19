import Foundation
import Network

/// One #one video episode, as the WordPress route answers it (spec-ios.md "Data",
/// episodes-route-notes.md). Video only in v1 (Thorsten, 2026-11-17).
struct Episode: Decodable, Identifiable, Equatable, Hashable {
    struct File: Decodable, Equatable, Hashable {
        let url: URL
        let width: Int?
        let height: Int?
        let mime: String?
        let bytes: Int?
        let list: Bool
    }

    struct Caption: Decodable, Equatable, Hashable {
        let lang: String
        let label: String?
        let url: URL
    }

    let postID: Int
    /// Nil for an item without a number (a "Kalenderwoche" item).
    let number: Int?
    let title: String
    let published: String
    let durationS: Int?
    let videoID: String
    let poster: URL?
    let link: URL?
    let notesHTML: String?
    let manifest: URL?
    let files: [File]
    let captions: [Caption]
    let chapters: URL?

    var id: String { videoID }

    enum CodingKeys: String, CodingKey {
        case postID = "post_id", number, title, published, durationS = "duration_s", videoID = "video_id"
        case poster, link, notesHTML = "notes_html", manifest, files, captions, chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postID = try c.decode(Int.self, forKey: .postID)
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        published = try c.decode(String.self, forKey: .published)
        durationS = try c.decodeIfPresent(Int.self, forKey: .durationS)
        videoID = try c.decode(String.self, forKey: .videoID)
        poster = try c.decodeIfPresent(URL.self, forKey: .poster)
        link = try c.decodeIfPresent(URL.self, forKey: .link)
        notesHTML = try c.decodeIfPresent(String.self, forKey: .notesHTML)
        manifest = try c.decodeIfPresent(URL.self, forKey: .manifest)
        files = try c.decodeIfPresent([File].self, forKey: .files) ?? []
        captions = try c.decodeIfPresent([Caption].self, forKey: .captions) ?? []
        chapters = try c.decodeIfPresent(URL.self, forKey: .chapters)
    }

    var publishedDate: Date? { Self.iso.date(from: published) }

    /// "Folge 527", or nothing for an item without a number.
    var numberLabel: String? { number.map { "Folge \($0)" } }

    /// "Fr., 14. Nov.", as the design writes dates.
    var dateLabel: String {
        guard let date = publishedDate else { return "" }
        return Self.dateFormat.string(from: date)
    }

    /// German captions first, else the first listed.
    var caption: Caption? { captions.first { $0.lang == "de" } ?? captions.first }

    /// The file to play: a listed one, by height, never by name (remux.mp4 can be the only
    /// listed one, episodes-route-notes.md). 1080 on Wi-Fi, 720 on cellular; nearest below the
    /// target, else the smallest listed above it.
    func file(cellular: Bool) -> File? {
        let listed = files.filter(\.list)
        let target = cellular ? 720 : 1080
        let below = listed.filter { ($0.height ?? 0) <= target }.max { ($0.height ?? 0) < ($1.height ?? 0) }
        return below ?? listed.min { ($0.height ?? .max) < ($1.height ?? .max) }
    }

    private static let iso: ISO8601DateFormatter = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format
    }()

    private static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "de_DE")
        format.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return format
    }()

    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// The route's answer: newest first; `next` goes back unchanged as `before=`.
struct EpisodesPage: Decodable, Equatable {
    let total: Int
    let next: String?
    let episodes: [Episode]
}

enum EpisodesError: Error, Equatable {
    /// 401: the token was refused.
    case signedOut
    /// 403: the account has no #one.
    case notMember
    /// 404: the chat switch is off, or the route is not deployed yet.
    case unavailable
    case failed
}

/// Where the episode list comes from: the WordPress route, or the bundled fixture.
protocol EpisodesSource: Sendable {
    func page(before: String?) async throws -> EpisodesPage
}

/// `GET /wp-json/iphoneblog/v1/one/episodes` with the app's Matrix token as Bearer, checked by
/// WordPress the way web-login checks it (DECISIONS.md). The host is the blog the app shows.
struct LiveEpisodesSource: EpisodesSource {
    let token: @Sendable () async -> String?
    var limit = 30

    static var endpoint: URL? {
        guard let blog = URL(string: Brand.blogWebURL), let host = blog.host() else { return nil }
        return URL(string: "\(blog.scheme ?? "https")://\(host)/wp-json/iphoneblog/v1/one/episodes")
    }

    func page(before: String?) async throws -> EpisodesPage {
        guard let endpoint = Self.endpoint, var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw EpisodesError.failed
        }
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
            + (before.map { [URLQueryItem(name: "before", value: $0)] } ?? [])
        guard let url = components.url, let token = await token() else { throw EpisodesError.signedOut }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try JSONDecoder().decode(EpisodesPage.self, from: data)
        case 401: throw EpisodesError.signedOut
        case 403: throw EpisodesError.notMember
        case 404: throw EpisodesError.unavailable
        default: throw EpisodesError.failed
        }
    }
}

/// The bundled fixture (one-tab-design/episodes-fixture.json), for UI tests and while the
/// route is not on the live site (IPHONEBLOG_EPISODES_FIXTURE=1, debug builds). With
/// IPHONEBLOG_EPISODES_LOCAL_VIDEO=1 every file and caption points at the bundled sample, so
/// a test can play.
struct FixtureEpisodesSource: EpisodesSource {
    var localVideo = false

    func page(before: String?) async throws -> EpisodesPage {
        guard let url = Bundle.main.url(forResource: "episodes-fixture", withExtension: "json") else { throw EpisodesError.unavailable }
        var text = try String(contentsOf: url, encoding: .utf8)
        if localVideo, let video = Bundle.main.url(forResource: "sample-video", withExtension: "mp4"),
           let captions = Bundle.main.url(forResource: "sample-captions.de", withExtension: "vtt") {
            let page = try JSONDecoder().decode(EpisodesPage.self, from: Data(text.utf8))
            for episode in page.episodes {
                for file in episode.files { text = text.replacingOccurrences(of: file.url.absoluteString, with: video.absoluteString) }
                for caption in episode.captions { text = text.replacingOccurrences(of: caption.url.absoluteString, with: captions.absoluteString) }
            }
        }
        return try JSONDecoder().decode(EpisodesPage.self, from: Data(text.utf8))
    }
}

/// The episode list for the hub and Videos: loads once per appearance, keeps what it had.
@MainActor
final class EpisodesModel: ObservableObject {
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var total = 0
    @Published private(set) var error: EpisodesError?
    @Published private(set) var hasLoaded = false
    private var next: String?
    private var loadingMore = false
    let source: EpisodesSource

    init(source: EpisodesSource) { self.source = source }

    /// The source the app uses: the fixture in debug runs that ask for it, else the route.
    static func source(token: @escaping @Sendable () async -> String?) -> EpisodesSource {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["IPHONEBLOG_EPISODES_FIXTURE"] == "1" {
            return FixtureEpisodesSource(localVideo: env["IPHONEBLOG_EPISODES_LOCAL_VIDEO"] == "1")
        }
        #endif
        return LiveEpisodesSource(token: token)
    }

    func load() async {
        do {
            let page = try await source.page(before: nil)
            if page.episodes != episodes { episodes = page.episodes }
            total = page.total
            next = page.next
            error = nil
        } catch let failure as EpisodesError {
            error = failure
        } catch {
            self.error = .failed
        }
        hasLoaded = true
    }

    /// The next page, when the list reaches its end.
    func loadMore() async {
        guard let next, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await source.page(before: next) else { return }
        let known = Set(episodes.map(\.id))
        episodes += page.episodes.filter { !known.contains($0.id) }
        self.next = page.next
    }
}

/// Wi-Fi or cellular, for the file choice (spec: 1080 on Wi-Fi, 720 on cellular).
final class NetworkKind: @unchecked Sendable {
    static let shared = NetworkKind()
    private let monitor = NWPathMonitor()
    private(set) var cellular = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi) }
        monitor.start(queue: DispatchQueue(label: "network-kind"))
    }
}
