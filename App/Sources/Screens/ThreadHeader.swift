import SwiftUI

/// The header of a #one thread (Philip, 2026-11-18, option 2): who started it and where. It
/// replaces Element X's header with the room's coloured letter, which said nothing to him.
/// The starter's small picture, "Thread von <Name>", "# <Raum>"; a tap opens the room at the
/// thread's root.
struct ThreadHeader: View {
    let thread: Router.ThreadRoute
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @State private var starter: (id: String, name: String)?

    var body: some View {
        Button {
            router.openMessage(roomID: thread.roomID, eventID: thread.rootEventID)
        } label: {
            HStack(spacing: 8) {
                if let starter {
                    MemberAvatar(userID: starter.id, name: starter.name, roomID: thread.roomID, size: 28)
                } else {
                    AvatarShape.of(28).fill(Color.secondary.opacity(0.2)).frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(starter.map { "Thread von \($0.name)" } ?? "Thread")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("# \(roomName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("thread.header")
        .accessibilityHint("Öffnet den Raum an dieser Stelle")
        .task(id: thread) { starter = await loadStarter() }
    }

    private var roomName: String {
        session.oneRooms.first { $0.id == thread.roomID }?.name
            ?? session.rooms.rooms.first { $0.id == thread.roomID }?.name
            ?? ""
    }

    private func loadStarter() async -> (id: String, name: String)? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let room = thread.roomID.addingPercentEncoding(withAllowedCharacters: allowed),
              let event = thread.rootEventID.addingPercentEncoding(withAllowedCharacters: allowed),
              let data = try? await session.api("GET", "/_matrix/client/v3/rooms/\(room)/event/\(event)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sender = json["sender"] as? String else { return nil }
        return (sender, await session.mentions.name(of: sender, session: session))
    }
}
