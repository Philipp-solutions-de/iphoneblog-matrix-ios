import Foundation
import MatrixRustSDK

/// Report and block (App Review Guideline 1.2: an app with user content must let people report
/// it and block abusive users). Reports go to Synapse's report API; the server mails each new one
/// to the moderators (infra, `docs/matrix.md`). Blocking is Matrix's ignore list: the server stops
/// sending that person's messages to this account, on every device.
///
/// The SDK reports a message (`Room.reportContent`) and ignores a user; it has no call for
/// reporting a user, so that one goes through `POST /_matrix/client/v3/users/{userId}/report`
/// (Matrix 1.14, Synapse 1.165 has it).
@MainActor
protocol ModerationBackend {
    func reportEvent(roomID: String, eventID: String, reason: String) async throws
    func reportUser(userID: String, reason: String) async throws
    func ignore(userID: String) async throws
    func unignore(userID: String) async throws
    func ignoredUsers() async throws -> [String]
}

enum Moderation {
    /// What somebody can say when reporting. The text goes to the moderators as it stands.
    enum Reason: String, CaseIterable, Identifiable {
        case spam = "Spam oder Werbung"
        case abuse = "Beleidigung oder Belästigung"
        case offensive = "Anstößige oder verbotene Inhalte"
        case other = "Etwas anderes"
        var id: String { rawValue }
    }

    /// The reason as the server receives it: the chosen reason, then the person's own words.
    static func reportText(_ reason: Reason, note: String) -> String {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? reason.rawValue : "\(reason.rawValue): \(note.prefix(1000))"
    }

    /// The report-user path. A Matrix ID holds `@` and `:`, which must be escaped in a path.
    static func reportUserPath(_ userID: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard userID.hasPrefix("@"), userID.contains(":"),
              let escaped = userID.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "/_matrix/client/v3/users/\(escaped)/report"
    }

    static func reportUserBody(_ reason: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["reason": reason])) ?? Data()
    }

    /// Whether this person may be reported or blocked from this account: never oneself.
    static func canModerate(userID: String, ownUserID: String) -> Bool {
        userID != ownUserID && userID.hasPrefix("@")
    }

    /// The address shown in Ich and as the App Store's support address for moderation: Alex,
    /// who also receives every report by mail (decided 2026-11-16). The row is hidden while it
    /// is nil.
    static let contactAddress: String? = "ao@iphoneblog.de"
}

/// The real backend, on the signed-in session.
@MainActor
struct SessionModeration: ModerationBackend {
    let session: ChatSession

    enum Failure: Error { case noRoom, badUserID }

    func reportEvent(roomID: String, eventID: String, reason: String) async throws {
        guard let room = try session.client.getRoom(roomId: roomID) else { throw Failure.noRoom }
        try await room.reportContent(eventId: eventID, reason: reason)
    }

    func reportUser(userID: String, reason: String) async throws {
        guard let path = Moderation.reportUserPath(userID) else { throw Failure.badUserID }
        _ = try await session.api("POST", path, body: Moderation.reportUserBody(reason))
    }

    func ignore(userID: String) async throws { try await session.client.ignoreUser(userId: userID) }
    func unignore(userID: String) async throws { try await session.client.unignoreUser(userId: userID) }
    func ignoredUsers() async throws -> [String] { try await session.client.ignoredUsers() }
}
