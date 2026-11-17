import Foundation

/// "Kontaktdaten teilen": the server holds the account's email address and phone number and
/// delivers the chosen ones to one person; the app only chooses and confirms. The endpoint is
/// the chat server's (infra, docs/matrix.md), on the homeserver with the Matrix access token.
@MainActor
struct ContactShare {
    enum Field: String, Codable { case email, phone }

    struct OwnDetails: Decodable, Equatable {
        let email: String?
        let phone: String?
    }

    let session: ChatSession

    static let ownPath = "/_iphoneblog/v1/contact/me"
    static let sharePath = "/_iphoneblog/v1/contact/share"

    /// What this account could share, so the sheet offers only those and shows their values.
    func ownDetails() async throws -> OwnDetails {
        try JSONDecoder().decode(OwnDetails.self, from: try await session.api("GET", Self.ownPath))
    }

    /// Sends the chosen details to one person.
    func share(_ fields: [Field], with userID: String) async throws {
        struct Request: Encodable { let to: String; let fields: [Field] }
        _ = try await session.api("POST", Self.sharePath, body: try JSONEncoder().encode(Request(to: userID, fields: fields)))
    }
}
