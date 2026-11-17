import SwiftUI

/// A person in the chat: name and picture, and "Kontaktdaten teilen" (Thorsten, 2026-11-17).
/// Opened by a tap on a name, an avatar or a mention; a long press opens the sharing at once.
struct ProfileSheet: View {
    let person: Router.Person
    @ObservedObject var session: ChatSession
    @ObservedObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var name: String?
    @State private var path: [String] = []

    private var displayName: String { name ?? MentionsModel.localpart(person.userID) }
    private var isMe: Bool { person.userID == session.userID }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 14) {
                InitialsAvatar(name: displayName, size: 84)
                    .padding(.top, 24)
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(person.userID)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
                if !isMe {
                    Button {
                        path = ["share"]
                    } label: {
                        Label("Kontaktdaten teilen", systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.teal)
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.top, 10)
                    .accessibilityIdentifier("profile.shareContact")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { _ in
                ContactShareView(recipientID: person.userID, recipientName: displayName, session: session) {
                    dismiss()
                    router.notice = "Kontaktdaten an \(displayName) gesendet."
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if person.shareNow, !isMe { path = ["share"] }
            name = try? await session.client.getProfile(userId: person.userID).displayName
        }
    }
}

/// Choose what to share, see who gets it and a warning, then confirm once more by name.
struct ContactShareView: View {
    let recipientID: String
    let recipientName: String
    @ObservedObject var session: ChatSession
    let done: () -> Void

    @State private var own: ContactShare.OwnDetails?
    @State private var loadError: String?
    @State private var shareEmail = false
    @State private var sharePhone = false
    @State private var confirming = false
    @State private var sending = false
    @State private var sendError: String?

    private var chosen: [ContactShare.Field] {
        (shareEmail ? [.email] : []) + (sharePhone ? [.phone] : [])
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("An", value: recipientName)
                    .accessibilityIdentifier("contactShare.recipient")
            }
            if let own {
                Section("Was du teilst") {
                    if let email = own.email {
                        Toggle(isOn: $shareEmail) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("E-Mail-Adresse")
                                Text(email).font(.footnote).foregroundStyle(Theme.ink3)
                            }
                        }
                        .accessibilityIdentifier("contactShare.email")
                    }
                    if let phone = own.phone {
                        Toggle(isOn: $sharePhone) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Telefonnummer")
                                Text(phone).font(.footnote).foregroundStyle(Theme.ink3)
                            }
                        }
                        .accessibilityIdentifier("contactShare.phone")
                    }
                    if own.email == nil, own.phone == nil {
                        Text("In deinem Konto ist weder eine E-Mail-Adresse noch eine Telefonnummer hinterlegt.")
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .tint(Theme.teal)
            } else if let loadError {
                Section { Text(loadError).foregroundStyle(Theme.ink2) }
            } else {
                Section { ProgressView() }
            }
            Section {
                Label {
                    Text("Nur \(recipientName) bekommt diese Daten. Teile sie nur mit Menschen, denen du "
                         + "vertraust: zurückholen kannst du sie nicht.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
            }
            if let sendError {
                Section { Text(sendError).foregroundStyle(.red) }
            }
            Section {
                Button {
                    confirming = true
                } label: {
                    HStack {
                        Text("An \(recipientName) senden")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(chosen.isEmpty || sending)
                .accessibilityIdentifier("contactShare.send")
            }
        }
        .navigationTitle("Kontaktdaten teilen")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Kontaktdaten an \(recipientName) senden?", isPresented: $confirming) {
            Button("Abbrechen", role: .cancel) { }
            Button("Senden") { Task { await send() } }
        } message: {
            Text(confirmText)
        }
        .task { await load() }
    }

    private var confirmText: String {
        var lines: [String] = []
        if shareEmail, let email = own?.email { lines.append("E-Mail: \(email)") }
        if sharePhone, let phone = own?.phone { lines.append("Telefon: \(phone)") }
        return lines.joined(separator: "\n") + "\n\n\(recipientName) kann sie danach behalten und weitergeben."
    }

    private func load() async {
        do {
            own = try await ContactShare(session: session).ownDetails()
        } catch {
            loadError = "Deine Kontaktdaten ließen sich nicht laden. Versuch es später noch einmal."
        }
    }

    private func send() async {
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await ContactShare(session: session).share(chosen, with: recipientID)
            done()
        } catch {
            sendError = "Das hat nicht geklappt. Es wurde nichts gesendet."
        }
    }
}
