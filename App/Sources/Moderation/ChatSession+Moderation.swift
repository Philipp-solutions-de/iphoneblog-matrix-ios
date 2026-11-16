import SwiftUI

/// What the conversation views asked for: a report or a profile. MainView presents it as a sheet.
enum ModerationRequest: Identifiable, Equatable {
    case reportMessage(roomID: String, eventID: String)
    case profile(userID: String)

    var id: String {
        switch self {
        case .reportMessage(let roomID, let eventID): return "report:\(roomID):\(eventID)"
        case .profile(let userID): return "profile:\(userID)"
        }
    }
}

/// The two ChatHost calls for moderation, kept apart from ChatSession.swift.
extension ChatSession {
    func showProfile(userID: String) {
        router.moderation = .profile(userID: userID)
    }

    func reportMessage(roomID: String, eventID: String) {
        router.moderation = .reportMessage(roomID: roomID, eventID: eventID)
    }

    /// A display name for a sheet's title: the room member's name, else the ID's local part.
    func displayName(of userID: String) async -> String {
        if let name = (try? await client.getProfile(userId: userID))?.displayName, !name.isEmpty { return name }
        return MentionsModel.localpart(userID)
    }
}

/// The sheet for a ModerationRequest.
struct ModerationSheet: View {
    let request: ModerationRequest
    let session: ChatSession
    @State private var name: String?

    var body: some View {
        let backend = SessionModeration(session: session)
        let notice: (String) -> Void = { session.router.notice = $0 }
        switch request {
        case .reportMessage(let roomID, let eventID):
            ReportSheet(subject: .message(roomID: roomID, eventID: eventID), backend: backend, done: notice)
        case .profile(let userID):
            UserProfileSheet(userID: userID, name: name ?? MentionsModel.localpart(userID),
                             ownUserID: session.userID, backend: backend, notice: notice)
                .task { name = await session.displayName(of: userID) }
        }
    }
}
