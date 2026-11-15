import SwiftUI
import UserNotifications

/// Every room with unread mentions of you, newest first in the room list's order.
struct MentionsView: View {
    @ObservedObject var router: Router
    @ObservedObject var rooms: RoomListModel

    var body: some View {
        NavigationStack {
            List(rooms.withMentions) { room in
                Button {
                    router.openRoom(room.id)
                } label: {
                    RoomRow(room: room)
                }
                .tint(.primary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if rooms.withMentions.isEmpty {
                    ContentUnavailableView("Keine neuen Erwähnungen", systemImage: "at",
                                           description: Text("Wenn dich jemand mit @ erwähnt, steht es hier."))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenTitle("@Erwähnungen")
            }
        }
    }
}

/// The serif title at the top of a tab, as on the Blog tab. The glass toolbar would cut it off.
struct ScreenTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.screenTitle)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(Theme.background)
    }
}

/// Ich: name and address, push, the blog account, privacy, sign out.
struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: ChatSession
    @ObservedObject private var push = PushCenter.shared
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        InitialsAvatar(name: session.displayName ?? session.userID, size: Theme.Size.profileAvatar)
                        Text(session.displayName ?? session.userID)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(session.userID)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Mitteilungen", value: pushText)
                    if push.authorization == .denied {
                        Button("In den Einstellungen erlauben") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                Section {
                    Button("Konto auf iphoneblog.de") {
                        Task {
                            if let url = await session.accountURL() { session.openURL(url) }
                        }
                    }
                    if let privacy = URL(string: Brand.oauthPolicyURI) {
                        Button("Datenschutz") { session.openURL(privacy) }
                    }
                    LabeledContent("Version", value: "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                }

                Section {
                    Button("Abmelden", role: .destructive) { confirmSignOut = true }
                        .accessibilityIdentifier("me.signOut")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { ScreenTitle("Ich") }
            .task { await push.refreshAuthorization() }
            .confirmationDialog("Auf diesem Gerät abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) {
                    Task { await model.signOut() }
                }
            } message: {
                Text("Deine Nachrichten bleiben auf dem Server. Du meldest dich mit deinem Blog-Konto wieder an.")
            }
        }
    }

    private var pushText: String {
        switch push.authorization {
        case .authorized, .provisional, .ephemeral: "An"
        case .denied: "Aus"
        default: "Noch nicht gefragt"
        }
    }
}

extension Bundle {
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
