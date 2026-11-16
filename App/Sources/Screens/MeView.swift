import SwiftUI

/// Ich, signed in (preview 5a): profile, the notification switches, the account, sign out.
struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: ChatSession
    @ObservedObject var prefs: NotificationPrefs
    @ObservedObject var router: Router
    @ObservedObject private var push = PushCenter.shared
    @State private var confirmSignOut = false

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
                    if session.isOneMember {
                        SettingsRow(label: "#one-Chat") {
                            Menu {
                                Picker("#one-Chat", selection: Binding(get: { prefs.channel }, set: prefs.setChannel)) {
                                    ForEach(NotificationPrefs.ChannelMode.allCases) { Text($0.rawValue).tag($0) }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(prefs.channel.rawValue)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12))
                                }
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.ink3)
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
                    .padding(.bottom, 30)
            }
        }
        .background(Theme.group)
        .task { await push.refreshAuthorization() }
        .task(id: session.oneChannelID) { await prefs.load() }
        .confirmationDialog("Auf diesem Gerät abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await model.signOut() } }
        } message: {
            Text("Deine Nachrichten bleiben auf dem Server. Du meldest dich mit deinem Blog-Konto wieder an.")
        }
    }

    private var profile: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: session.displayName ?? MentionsModel.localpart(session.userID), size: Theme.Size.profileAvatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName ?? MentionsModel.localpart(session.userID))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(session.userID)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink3)
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

/// Ich, signed out (preview 5b): sign in with the blog account, register, privacy, imprint.
struct GuestMeView: View {
    @ObservedObject var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScreenTitle("Ich")
                VStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityLabel("iPhoneBlog.de")
                    Text("Melde dich mit deinem Konto von iphoneblog.de an. Ein eigenes Passwort für die App gibt es nicht.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                    Button { router.showSignIn = true } label: {
                        Text("Mit iphoneblog.de anmelden").frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
                    }
                    .buttonStyle(FilledButton(fill: Theme.coralButton))
                    .accessibilityIdentifier("me.signIn")
                    HStack(spacing: 4) {
                        Text("Noch kein Konto?").foregroundStyle(Theme.ink3)
                        Button("Registrieren") {
                            if let url = URL(string: Brand.registerURL) { router.presentedURL = url }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.teal)
                    }
                    .font(.system(size: 15))
                }
                .padding(EdgeInsets(top: 28, leading: 20, bottom: 22, trailing: 20))
                .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner))
                .padding(.horizontal, Theme.Space.page)

                Text("Lesen geht auch ohne Anmeldung: der Blog und die Diskussionen unter jedem Artikel.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)

                SettingsGroup {
                    LinkRow(label: "Datenschutz") {
                        if let url = URL(string: Brand.oauthPolicyURI) { router.presentedURL = url }
                    }
                    LinkRow(label: "Impressum") {
                        if let url = URL(string: Brand.imprintURL) { router.presentedURL = url }
                    }
                }
                .padding(.top, 22)

                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
            }
        }
        .background(Theme.group)
    }
}
