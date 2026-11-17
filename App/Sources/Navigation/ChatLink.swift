import Foundation

/// Readable links to rooms and messages on our own domain (Thorsten, 2026-11-17, from Philip's
/// report: "Link kopieren" gave a raw matrix.to link with room ID and via). One form, agreed with
/// the web chat at chat.iphoneblog.de, which routes the same paths and copies the same links:
///
///   https://chat.iphoneblog.de/#/<room>              the room
///   https://chat.iphoneblog.de/#/<room>/$<event>     a message, thread replies included
///
/// <room> is the canonical alias's localpart on our server, else the room ID, percent-encoded.
/// The link carries no thread root: the opener reads the event and opens its thread if it has
/// one, so a link stays right if a message moves into a thread. The chat server's
/// apple-app-site-association hands these links to the app when it is installed. matrix.to links
/// to rooms and messages keep working: parse reads both.
struct ChatLink: Equatable {
    /// A room by alias (full, "#one-chat:iphoneblog.de") or by ID ("!abc…", room v12 has no server).
    let room: String
    let eventID: String?

    init(room: String, eventID: String? = nil) {
        self.room = room
        self.eventID = eventID
    }

    /// The web chat's origin and our server name, from brand.env.
    static var base: URL { URL(string: Brand.homeserverURL)! } // swiftlint:disable:this force_unwrapping
    static var serverName: String { Brand.serverName }

    // MARK: Build

    /// The link "Link kopieren" copies. `alias` is the room's canonical alias, if any.
    static func url(roomID: String, alias: String?, eventID: String?) -> URL? {
        var segments = [roomSegment(roomID: roomID, alias: alias)]
        if let eventID { segments.append(eventID) }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.percentEncodedFragment = "/" + segments.map(encode).joined(separator: "/")
        return components?.url
    }

    /// An alias on our own server shortens to its localpart; anything else stays the room ID.
    private static func roomSegment(roomID: String, alias: String?) -> String {
        if let alias, alias.hasPrefix("#"), alias.hasSuffix(":" + serverName) {
            return String(alias.dropFirst().dropLast(serverName.count + 1))
        }
        return roomID
    }

    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~$")
        return set
    }()

    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }

    // MARK: Parse

    /// Our chat links and matrix.to links to a room or a room's message. Users, other hosts and
    /// the web chat's own view states (#/<room>/t/…) return nil; the caller opens those as before.
    static func parse(_ url: URL) -> ChatLink? {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let fragment = url.fragment(percentEncoded: true) ?? ""
        if host == base.host?.lowercased() { return parseOwn(fragment) }
        if host == "matrix.to" { return parseMatrixTo(fragment) }
        return nil
    }

    private static func segments(of fragment: String) -> [String] {
        // "?via=…" belongs to matrix.to; our links carry none, but a pasted one may.
        let path = fragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        return path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func parseOwn(_ fragment: String) -> ChatLink? {
        let parts = segments(of: fragment)
        guard let first = parts.first, parts.count <= 2 else { return nil }
        // A room ID stays as it is; an alias localpart gets our server back.
        let room = first.hasPrefix("!") ? first
            : first.hasPrefix("#") ? (first.contains(":") ? first : "\(first):\(serverName)")
            : "#\(first):\(serverName)"
        guard parts.count == 2 else { return ChatLink(room: room) }
        guard parts[1].hasPrefix("$"), parts[1].count > 1 else { return nil }
        return ChatLink(room: room, eventID: parts[1])
    }

    private static func parseMatrixTo(_ fragment: String) -> ChatLink? {
        let parts = segments(of: fragment)
        guard let first = parts.first, first.hasPrefix("!") || first.hasPrefix("#") else { return nil }
        if parts.count == 1 { return ChatLink(room: first) }
        if parts.count == 2, parts[1].hasPrefix("$") { return ChatLink(room: first, eventID: parts[1]) }
        return nil
    }
}
