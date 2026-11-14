import SwiftUI

/// Channels, then direct messages; the open conversation beside them on iPad, on top on iPhone.
struct ChatsView: View {
    let session: ChatSession
    @ObservedObject var router: Router
    @ObservedObject var rooms: RoomListModel
    @State private var search = ""
    @State private var columns = NavigationSplitViewVisibility.all

    private func matching(_ list: [RoomSummary]) -> [RoomSummary] {
        let term = search.trimmingCharacters(in: .whitespaces)
        return term.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            VStack(spacing: 0) {
                header
                SearchField(text: $search)
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.bottom, 4)
                List(selection: $router.selectedRoomID) {
                    Section {
                        ForEach(matching(rooms.channels)) { room in
                            RoomRow(room: room).tag(room.id).listRowStyle()
                        }
                    } header: {
                        SectionHeader("Kanäle")
                    }
                    if !matching(rooms.directMessages).isEmpty {
                        Section {
                            ForEach(matching(rooms.directMessages)) { room in
                                RoomRow(room: room).tag(room.id).listRowStyle()
                            }
                        } header: {
                            SectionHeader("Direktnachrichten")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if !rooms.hasLoaded {
                        ProgressView()
                    } else if rooms.rooms.isEmpty {
                        ContentUnavailableView("Noch keine Kanäle", systemImage: "number",
                                               description: Text("Sobald du in einem Kanal bist, steht er hier."))
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle(Brand.appName)
        } detail: {
            NavigationStack(path: $router.threadPath) {
                Group {
                    if let roomID = router.selectedRoomID {
                        ChatScreens.provider.roomScreen(roomID: roomID, host: session)
                            .id(roomID)
                    } else {
                        Text("Wähl einen Kanal.")
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .navigationDestination(for: Router.ThreadRoute.self) { route in
                    ChatScreens.provider.threadScreen(roomID: route.roomID, rootEventID: route.rootEventID, host: session)
                }
            }
        }
        .tint(Theme.teal)
    }

    /// "iphoneblog" in the blog's serif, your initials on the right (a tap opens Ich).
    private var header: some View {
        HStack {
            Text(Brand.appName)
                .font(Theme.Font.screenTitle)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                router.tab = .me
            } label: {
                InitialsAvatar(name: session.displayName ?? session.userID, size: Theme.Size.headerAvatar)
            }
            .accessibilityLabel("Ich")
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// Small grey capitals above a group of rows.
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(Theme.Font.sectionHeader)
            .tracking(0.3)
            .foregroundStyle(Theme.ink3)
            .padding(.top, Theme.Space.section - 8)
    }
}

/// The rounded search field under the header.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
            TextField("Suchen", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .font(.system(size: 15.5))
        .padding(.horizontal, 12)
        .frame(height: Theme.Size.searchHeight)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Size.corner))
    }
}

private extension View {
    func listRowStyle() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Theme.Space.row, leading: Theme.Space.page,
                                      bottom: Theme.Space.row, trailing: Theme.Space.page))
            .listRowBackground(Color.clear)
    }
}

/// One channel or person: bold when unread, a coral badge when something is for you,
/// a grey number when there are only new messages.
struct RoomRow: View {
    let room: RoomSummary

    var body: some View {
        HStack(spacing: Theme.Space.rowGap) {
            if room.isDirect {
                InitialsAvatar(name: room.name, size: Theme.Size.rowIcon)
            } else {
                Text("#")
                    .font(Theme.Font.rowHash)
                    .foregroundStyle(room.hasUnread ? Theme.ink : Theme.ink3)
                    .frame(width: Theme.Size.rowIcon)
            }
            Text(room.name)
                .font(Theme.Font.rowTitle)
                .fontWeight(room.hasUnread ? .semibold : .regular)
                .foregroundStyle(Theme.ink)
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
                .badgeStyle(background: Theme.quietBadge, foreground: Theme.ink2)
        } else if room.isMarkedUnread {
            Circle().fill(Theme.tealBright).frame(width: Theme.Size.unreadDot, height: Theme.Size.unreadDot)
        }
    }
}

private extension View {
    func badgeStyle(background: Color, foreground: some ShapeStyle) -> some View {
        font(Theme.Font.badge)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(minWidth: Theme.Size.badgeHeight, minHeight: Theme.Size.badgeHeight)
            .background(background, in: Capsule())
    }
}

/// A coloured circle with initials, the same colour for the same name every time.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 36


    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let index = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Theme.avatarColors.count
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.avatarColors[index], in: Circle())
            .accessibilityHidden(true)
    }
}
