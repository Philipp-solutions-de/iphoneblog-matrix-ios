import SwiftUI

/// Channels, then direct messages; the open conversation beside them on iPad, on top on iPhone.
struct ChatsView: View {
    let session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject var rooms: RoomListModel

    var body: some View {
        NavigationSplitView {
            List(selection: $router.selectedRoomID) {
                Section("Kanäle") {
                    ForEach(rooms.channels) { room in
                        RoomRow(room: room).tag(room.id)
                    }
                }
                if !rooms.directMessages.isEmpty {
                    Section("Direktnachrichten") {
                        ForEach(rooms.directMessages) { room in
                            RoomRow(room: room).tag(room.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if !rooms.hasLoaded {
                    ProgressView()
                } else if rooms.rooms.isEmpty {
                    ContentUnavailableView("Noch keine Kanäle", systemImage: "number",
                                           description: Text("Sobald du in einem Kanal bist, steht er hier."))
                }
            }
            .navigationTitle(Brand.appName)
        } detail: {
            NavigationStack(path: $router.threadPath) {
                Group {
                    if let roomID = router.selectedRoomID {
                        ChatScreens.provider.roomScreen(roomID: roomID, host: session)
                            .id(roomID)
                    } else {
                        Text("Wähl einen Kanal.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationDestination(for: Router.ThreadRoute.self) { route in
                    ChatScreens.provider.threadScreen(roomID: route.roomID, rootEventID: route.rootEventID, host: session)
                }
            }
        }
    }
}

/// One channel or person: bold when unread, a coral badge when something is for you,
/// a grey number when there are only new messages.
struct RoomRow: View {
    let room: RoomSummary

    var body: some View {
        HStack(spacing: 12) {
            if room.isDirect {
                InitialsAvatar(name: room.name, size: 28)
            } else {
                Text("#")
                    .font(.title3)
                    .foregroundStyle(room.hasUnread ? .primary : .secondary)
                    .frame(width: 28)
            }
            Text(room.name)
                .fontWeight(room.hasUnread ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            badge
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("room.\(room.name)")
    }

    @ViewBuilder private var badge: some View {
        if room.unreadMentions > 0 {
            Text("@ \(room.unreadMentions)")
                .badgeStyle(background: Theme.coral, foreground: .white)
        } else if room.isDirect, room.unreadMessages > 0 {
            Text("\(room.unreadMessages)")
                .badgeStyle(background: Theme.coral, foreground: .white)
        } else if room.unreadMessages > 0 {
            Text("\(room.unreadMessages)")
                .badgeStyle(background: Color(.systemFill), foreground: .secondary)
        } else if room.isMarkedUnread {
            Circle().fill(Theme.teal).frame(width: 9, height: 9)
        }
    }
}

private extension View {
    func badgeStyle(background: Color, foreground: some ShapeStyle) -> some View {
        font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(background, in: Capsule())
    }
}

/// A coloured circle with initials, the same colour for the same name every time.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 36

    private static let colors: [Color] = [
        Color(red: 0.08, green: 0.59, blue: 0.57), Color(red: 0.88, green: 0.64, blue: 0.23),
        Color(red: 0.49, green: 0.42, blue: 0.77), Color(red: 0.92, green: 0.41, blue: 0.43),
        Color(red: 0.30, green: 0.55, blue: 0.79), Color(red: 0.37, green: 0.55, blue: 0.35)
    ]

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let index = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Self.colors.count
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.colors[index], in: Circle())
            .accessibilityHidden(true)
    }
}
