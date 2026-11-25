import PhotosUI
import SwiftUI

/// Ich, signed in (preview 5a): profile, the notification switches, the account, sign out.
struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: ChatSession
    @ObservedObject var prefs: NotificationPrefs
    @ObservedObject var router: Router
    @ObservedObject private var push = PushCenter.shared
    @State private var confirmSignOut = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var avatarBusy = false
    /// The picked picture while the person places it (AvatarCropView).
    @State private var cropping: PickedImage?
    /// The upload's share, 0 to 1, while it runs (Alex: the web gave no feedback at all).
    @State private var uploadProgress: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScreenTitle("Ich")
                profile

                GroupHeader("Mitteilungen")
                SettingsGroup {
                    SettingsRow(label: "Neue Artikel") {
                        Toggle("", isOn: Binding(get: { prefs.newArticles }, set: prefs.setNewArticles)).labelsHidden()
                    }
                    SettingsRow(label: "Antworten auf meine Beiträge") {
                        // A reply names whom it answers, so it arrives as a mention: the same rule.
                        Toggle("", isOn: Binding(get: { prefs.mentions }, set: prefs.setMentions)).labelsHidden()
                    }
                    SettingsRow(label: "@Mentions") {
                        Toggle("", isOn: Binding(get: { prefs.mentions }, set: prefs.setMentions)).labelsHidden()
                    }
                    // One row per #one room (testers: too many pushes). "Nur Erwähnungen" is the
                    // default; "Alle" pushes every message there, "Aus" not even mentions.
                    if session.isOneMember {
                        ForEach(session.oneRooms) { room in
                            SettingsRow(label: "#one · \(room.name)") {
                                Menu {
                                    Picker(room.name, selection: Binding(get: { prefs.roomModes[room.id] ?? .mentions },
                                                                         set: { prefs.setMode($0, roomID: room.id) })) {
                                        ForEach(NotificationPrefs.ChannelMode.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text((prefs.roomModes[room.id] ?? .mentions).rawValue)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12))
                                    }
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.ink3)
                                }
                                .accessibilityIdentifier("me.roomMode.\(room.name)")
                            }
                        }
                    }
                }
                .tint(Theme.tealBright)
                .disabled(!prefs.hasLoaded)
                if push.authorization == .denied {
                    Button("Mitteilungen sind in den Einstellungen aus. Dort erlauben") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.teal)
                    .padding(.horizontal, Theme.Space.page + 14)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupHeader("Konto")
                SettingsGroup {
                    LinkRow(label: "Konto auf iphoneblog.de", external: true) {
                        Task { if let url = await session.accountURL() { router.presentedURL = url } }
                    }
                    LinkRow(label: "Datenschutz") {
                        if let url = URL(string: Brand.oauthPolicyURI) { router.presentedURL = url }
                    }
                }
                MeModerationRows(session: session, router: router)

                SettingsGroup {
                    Button { confirmSignOut = true } label: {
                        SettingsRow(label: "Abmelden", labelColor: Theme.coralText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("me.signOut")
                }
                .padding(.top, 28)

                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 18)
                // The last launch's timing, for testers to send (2026-11-21, docs/performance.md):
                // a tap copies build, device and every start-up step with its time.
                if let summary = StartTrace.lastSummary {
                    Button {
                        UIPasteboard.general.string = StartTrace.lastReport
                        router.notice = "Ladezeit kopiert."
                    } label: {
                        Text("Ladezeit beim letzten Start: \(summary)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Kopiert die Zeiten")
                    .accessibilityIdentifier("me.startTiming")
                    .padding(.top, 4)
                }
                Color.clear.frame(height: 30)
            }
        }
        .background(Theme.group)
        .task { await push.refreshAuthorization() }
        // The room rows under Mitteilungen need the #one list, which only the #one tab loaded:
        // someone who went to Ich first saw no rooms there.
        .task(id: session.isOneMember) { await session.loadOneRooms() }
        .task(id: session.oneRooms.map(\.id)) { await prefs.load() }
        .confirmationDialog("Auf diesem Gerät abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await model.signOut() } }
        } message: {
            Text("Deine Nachrichten bleiben auf dem Server. Du meldest dich mit deinem Blog-Konto wieder an.")
        }
    }

    /// The old picture stays until the new one is on the server; the progress shows meanwhile.
    private func upload(_ square: UIImage, _ jpeg: Data) {
        uploadProgress = 0
        Task {
            defer { uploadProgress = nil }
            do {
                try await session.setAvatar(jpeg: jpeg, image: square) { uploadProgress = $0 }
                router.notice = "Profilbild gespeichert."
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
                router.notice = "Keine Verbindung. Dein altes Profilbild bleibt."
            } catch {
                router.notice = "Das Profilbild ließ sich nicht speichern. Dein altes bleibt."
            }
        }
    }

    private var profile: some View {
        HStack(spacing: 14) {
            // The picture is the person's own (testers: "Profilbilder lassen sich nicht setzen");
            // the name stays the blog's.
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ZStack {
                    if let avatar = session.avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                            .frame(width: Theme.Size.profileAvatar, height: Theme.Size.profileAvatar)
                            .clipShape(AvatarShape.of(Theme.Size.profileAvatar))
                    } else {
                        InitialsAvatar(name: session.displayName ?? MentionsModel.localpart(session.userID), size: Theme.Size.profileAvatar)
                    }
                    if let uploadProgress {
                        AvatarShape.of(Theme.Size.profileAvatar).fill(.black.opacity(0.45))
                            .frame(width: Theme.Size.profileAvatar, height: Theme.Size.profileAvatar)
                        ProgressView(value: uploadProgress)
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .accessibilityLabel("Profilbild wird hochgeladen")
                            .accessibilityValue("\(Int(uploadProgress * 100)) Prozent")
                            .accessibilityIdentifier("me.avatarProgress")
                    } else if avatarBusy {
                        ProgressView()
                    }
                }
            }
            .accessibilityLabel("Profilbild wählen")
            .accessibilityIdentifier("me.avatar")
            .contextMenu {
                if session.avatar != nil {
                    Button("Profilbild entfernen", role: .destructive) {
                        Task {
                            avatarBusy = true
                            try? await session.removeAvatar()
                            avatarBusy = false
                        }
                    }
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    avatarBusy = true
                    defer { avatarBusy = false; pickedPhoto = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        router.notice = "Dieses Bild lässt sich nicht öffnen. Wähl ein anderes."
                        return
                    }
                    cropping = PickedImage(image: image)
                }
            }
            .fullScreenCover(item: $cropping) { picked in
                AvatarCropView(image: picked.image, onCancel: { cropping = nil }) { square, jpeg in
                    cropping = nil
                    upload(square, jpeg)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName ?? MentionsModel.localpart(session.userID))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(session.userID)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink3)
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) { Text(session.avatar == nil ? "Bild wählen" : "Bild ändern") }
                    if session.avatar != nil {
                        Button("Bild entfernen") {
                            Task {
                                avatarBusy = true
                                try? await session.removeAvatar()
                                avatarBusy = false
                            }
                        }
                        .accessibilityIdentifier("me.avatarRemove")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.teal)
                .padding(.top, 2)
                if session.isOneMember {
                    Text("#one-Mitglied")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.coralText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.coralSoft, in: Capsule())
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.Size.corner))
        .padding(.horizontal, Theme.Space.page)
    }
}

/// A picked picture as a sheet item.
struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
