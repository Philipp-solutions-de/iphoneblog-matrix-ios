import SwiftUI

/// What the conversation views asked for: a report. MainView presents it as a sheet. A person's
/// profile (with "Melden" and "Blockieren") is the app's ProfileSheet, opened through openUser.
enum ModerationRequest: Identifiable, Equatable {
    case reportMessage(roomID: String, eventID: String)

    var id: String {
        switch self {
        case .reportMessage(let roomID, let eventID): return "report:\(roomID):\(eventID)"
        }
    }
}

/// The ChatHost call for moderation, kept apart from ChatSession.swift.
extension ChatSession {
    func reportMessage(roomID: String, eventID: String) {
        router.moderation = .reportMessage(roomID: roomID, eventID: eventID)
    }
}

/// The sheet for a ModerationRequest.
struct ModerationSheet: View {
    let request: ModerationRequest
    let session: ChatSession

    var body: some View {
        switch request {
        case .reportMessage(let roomID, let eventID):
            ReportSheet(subject: .message(roomID: roomID, eventID: eventID), backend: SessionModeration(session: session)) {
                session.router.notice = $0
            }
        }
    }
}
