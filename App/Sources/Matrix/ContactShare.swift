import Foundation

/// "Kontaktdaten teilen" (Thorsten, 2026-11-17): one #one member sends another their email
/// address and/or a phone number. The chat server holds the address (the blog account's, never
/// sent by the app) and mails the recipient; nothing appears in the chat. Contract: infra
/// docs/matrix.md, "Sharing contact details".
@MainActor
struct ContactShare {
    enum Field: String, Codable { case email, phone }

    /// What this account may share: `fields` lists what the server offers, `email` the address
    /// it would send. A phone number is typed each time and stored nowhere.
    struct Offer: Decodable, Equatable {
        let member: Bool
        let fields: [Field]
        let email: String?
    }

    enum Failure: Error, Equatable {
        case notMember, recipientUnavailable, tooMany(retryMinutes: Int?), mailFailed, invalid, other

        var message: String {
            switch self {
            case .notMember: "Kontaktdaten teilen können nur #one-Mitglieder."
            case .recipientUnavailable: "An diese Person lassen sich gerade keine Kontaktdaten senden."
            case .tooMany(let minutes?): "Du hast gerade oft Kontaktdaten geteilt. Versuch es in \(minutes) Minuten noch einmal."
            case .tooMany(nil): "Du hast gerade oft Kontaktdaten geteilt. Versuch es später noch einmal."
            case .mailFailed: "Die E-Mail ging nicht raus. Versuch es später noch einmal."
            case .invalid: "Das lässt sich so nicht senden. Prüf die Telefonnummer."
            case .other: "Das hat nicht geklappt. Es wurde nichts gesendet."
            }
        }

        static func from(status: Int, body: Data) -> Failure {
            switch status {
            case 400: return .invalid
            case 403: return .notMember
            case 404: return .recipientUnavailable
            case 429:
                let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                let millis = json?["retry_after_ms"] as? Double
                return .tooMany(retryMinutes: millis.map { max(1, Int(($0 / 60000).rounded(.up))) })
            case 502: return .mailFailed
            default: return .other
            }
        }
    }

    struct Request: Encodable, Equatable {
        let to: String
        let fields: [Field]
        let phone: String?
        let note: String?
        let dryRun: Bool?

        enum CodingKeys: String, CodingKey { case to, fields, phone, note, dryRun = "dry_run" }
    }

    let session: ChatSession
    static let path = "/_iphoneblog/v1/contact-share"

    /// Only another person, never the room bot (@iphoneblog).
    static func canShare(with userID: String, me: String) -> Bool {
        userID != me && MentionsModel.localpart(userID) != "iphoneblog"
    }

    /// 6 to 17 digits, written with + ( ) / . - and spaces, as the server accepts it.
    static func isPhoneNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber).count
        return (6...17).contains(digits) && trimmed.allSatisfy { $0.isNumber || "+()/.- ".contains($0) }
    }

    static func request(to userID: String, fields: [Field], phone: String, note: String) -> Request {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Request(to: userID, fields: fields,
                       phone: fields.contains(.phone) ? phone.trimmingCharacters(in: .whitespaces) : nil,
                       note: note.isEmpty ? nil : String(note.prefix(500)), dryRun: nil)
    }

    func offer() async throws -> Offer {
        #if DEBUG
        if Self.stubbed { return Offer(member: true, fields: [.email, .phone], email: "tester@example.org") }
        #endif
        let (data, status) = try await session.call("GET", Self.path)
        guard status == 200 else { throw Failure.from(status: status, body: data) }
        return try JSONDecoder().decode(Offer.self, from: data)
    }

    func send(_ request: Request) async throws {
        #if DEBUG
        if Self.stubbed {
            try await Task.sleep(for: .milliseconds(300))
            return
        }
        #endif
        let (data, status) = try await session.call("POST", Self.path, body: try JSONEncoder().encode(request))
        guard status == 200 else { throw Failure.from(status: status, body: data) }
    }

    #if DEBUG
    /// UI tests against the local test server, which has no such endpoint
    /// (IPHONEBLOG_CONTACT_SHARE_STUB=1).
    private static var stubbed: Bool { ProcessInfo.processInfo.environment["IPHONEBLOG_CONTACT_SHARE_STUB"] == "1" }
    #endif
}
