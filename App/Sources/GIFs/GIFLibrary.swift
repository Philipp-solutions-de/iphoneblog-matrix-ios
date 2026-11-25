import CryptoKit
import Foundation

/// "GIFs aus dem Chat": the library of GIFs members posted in #one, served by our server
/// (gif-library.md, infra docs/matrix.md "GIFs from the chat"). Members only; the server checks
/// the Matrix token. Nothing here leaves the chat: no public page, no download, no export.
struct LibraryGIF: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let mxc: String
    let width: Int?
    let height: Int?
    let size: Int?
    var tags: [String]

    /// A GIF without tags shows "#?": search finds it only by its file name or caption.
    var needsTags: Bool { tags.isEmpty }

    private enum CodingKeys: String, CodingKey { case id, mxc, width, height, size, tags }

    init(id: String, mxc: String, width: Int?, height: Int?, size: Int?, tags: [String]) {
        self.id = id
        self.mxc = mxc
        self.width = width
        self.height = height
        self.size = size
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        mxc = try c.decode(String.self, forKey: .mxc)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

struct GIFPage: Decodable, Equatable {
    let gifs: [LibraryGIF]
    let next: String?
}

/// The lookup before sending a GIF of one's own: whether the composer asks for tags.
struct GIFLookup: Decodable, Equatable {
    let id: String?
    let needsTag: Bool

    private enum CodingKeys: String, CodingKey { case id, needsTag = "needs_tag" }
}

enum GIFLibraryError: Error, Equatable {
    /// Not a #one member (403): the library is members only.
    case notMember
    /// Too many (429).
    case tooMany
    /// A tag the server would refuse; the text says why.
    case badTag(String)
    case failed
}

enum GIFSort: String, CaseIterable, Identifiable {
    case popular, new
    var id: String { rawValue }
    var title: String { self == .popular ? "Beliebt" : "Neu" }
}

/// The server's tag rules, checked before anything leaves (gif-library.md, "Tags"): 3 to 24
/// characters with at least 3 letters, only letters, digits, spaces and "-"; lower case with
/// single spaces. The block list stays on the server.
enum GIFTags {
    static let maxPerGIF = 10

    static func normalised(_ tag: String) -> String {
        tag.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// nil when the tag is fine, else why not, in the app's words.
    static func problem(_ raw: String) -> String? {
        let tag = normalised(raw)
        guard (3...24).contains(tag.count) else { return "„\(raw)“: 3 bis 24 Zeichen." }
        guard tag.filter(\.isLetter).count >= 3 else { return "„\(raw)“: mindestens 3 Buchstaben." }
        guard tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }) else {
            return "„\(raw)“: nur Buchstaben, Ziffern, Leerzeichen und -."
        }
        return nil
    }

    /// "jubeln, facepalm" → ["jubeln", "facepalm"], or the first problem.
    static func parse(_ text: String) -> Result<[String], GIFLibraryError> {
        let parts = text.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count > maxPerGIF { return .failure(.badTag("Höchstens \(maxPerGIF) Schlagworte.")) }
        for part in parts { if let problem = problem(part) { return .failure(.badTag(problem)) } }
        var seen = Set<String>()
        return .success(parts.map(normalised).filter { seen.insert($0).inserted })
    }

    /// The id the server knows a GIF by: the SHA-256 of the file, in hex.
    static func id(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The library's calls, with the reader's token.
@MainActor
final class GIFLibraryAPI {
    private let session: ChatSession

    init(session: ChatSession) {
        self.session = session
    }

    func list(sort: GIFSort, query: String, from: String?) async throws -> GIFPage {
        var items = [URLQueryItem(name: "sort", value: sort.rawValue), URLQueryItem(name: "limit", value: "60")]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        if let from { items.append(URLQueryItem(name: "from", value: from)) }
        return try JSONDecoder().decode(GIFPage.self, from: try await call("GET", "", query: items))
    }

    func lookup(sha256: String) async throws -> GIFLookup {
        try JSONDecoder().decode(GIFLookup.self, from: try await call("GET", "/lookup", query: [URLQueryItem(name: "sha256", value: sha256)]))
    }

    /// Replaces a GIF's tags (PATCH); an empty list removes them all.
    func replaceTags(_ tags: [String], of id: String) async throws -> [String] {
        try tagAnswer(try await call("PATCH", "/\(id)/tags", body: ["tags": tags]))
    }

    /// Adds tags (POST), as the composer does for a GIF new to the library.
    func addTags(_ tags: [String], to id: String) async throws -> [String] {
        try tagAnswer(try await call("POST", "/\(id)/tags", body: ["tags": tags]))
    }

    func report(_ id: String) async throws {
        _ = try await call("POST", "/\(id)/report", body: [String: String]())
    }

    private func tagAnswer(_ data: Data) throws -> [String] {
        struct Answer: Decodable { let tags: [String] }
        return try JSONDecoder().decode(Answer.self, from: data).tags
    }

    /// `<homeserver>/_iphoneblog/v1/gifs<path>`; UI tests point it at the fixture server
    /// (IPHONEBLOG_GIFS_URL, debug builds).
    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        var components = URLComponents()
        components.queryItems = query.isEmpty ? nil : query
        let suffix = path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        #if DEBUG
        if let base = ProcessInfo.processInfo.environment["IPHONEBLOG_GIFS_URL"], let url = URL(string: base + suffix) {
            return try await direct(method, url, body: data)
        }
        #endif
        do {
            return try await session.api(method, "/_iphoneblog/v1/gifs" + suffix, body: data)
        } catch let error as URLError where error.code == .badServerResponse {
            throw session.lastAPIStatus == 403 ? GIFLibraryError.notMember
                : session.lastAPIStatus == 429 ? GIFLibraryError.tooMany
                : session.lastAPIStatus == 400 ? GIFLibraryError.badTag("Das Schlagwort nimmt der Server nicht an.")
                : GIFLibraryError.failed
        }
    }

    #if DEBUG
    private func direct(_ method: String, _ url: URL, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try session.client.session().accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 403: throw GIFLibraryError.notMember
        case 429: throw GIFLibraryError.tooMany
        case 400: throw GIFLibraryError.badTag("Das Schlagwort nimmt der Server nicht an.")
        default: throw GIFLibraryError.failed
        }
    }
    #endif
}
