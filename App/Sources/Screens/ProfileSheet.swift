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
    @State private var detent: PresentationDetent = .medium

    private var displayName: String { name ?? MentionsModel.localpart(person.userID) }
    /// Another person, not oneself and not the room bot: block and report.
    private var isOther: Bool { ContactShare.canShare(with: person.userID, me: session.userID) }
    @State private var blocked = false
    @State private var confirmBlock = false
    @State private var reporting = false
    @State private var reason = ""
    /// Members only, and only with another person (not oneself, not the room bot).
    private var canShare: Bool { router.isMember && ContactShare.canShare(with: person.userID, me: session.userID) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 14) {
                MemberAvatar(userID: person.userID, name: displayName, size: 84)
                    .padding(.top, 24)
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(person.userID)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
                if canShare {
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
                if isOther {
                    HStack(spacing: 12) {
                        Button(blocked ? "Blockierung aufheben" : "Blockieren", role: blocked ? nil : .destructive) {
                            if blocked { Task { await setBlocked(false) } } else { confirmBlock = true }
                        }
                        .accessibilityIdentifier("profile.block")
                        Button("Melden", role: .destructive) { reporting = true }
                            .accessibilityIdentifier("profile.report")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
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
        // The sharing form needs the whole height; the profile alone fits in half.
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: path) { _, path in if !path.isEmpty { detent = .large } }
        .presentationDragIndicator(.visible)
        .alert("\(displayName) blockieren?", isPresented: $confirmBlock) {
            Button("Abbrechen", role: .cancel) { }
            Button("Blockieren", role: .destructive) { Task { await setBlocked(true) } }
        } message: {
            Text("Du siehst keine Nachrichten von \(displayName) mehr. \(displayName) erfährt davon nichts. "
                 + "Unter dem Profil hebst du es wieder auf.")
        }
        .alert("\(displayName) melden", isPresented: $reporting) {
            TextField("Was ist passiert?", text: $reason)
            Button("Abbrechen", role: .cancel) { reason = "" }
            Button("Melden", role: .destructive) { Task { await report() } }
        } message: {
            Text("Das Team sieht die Meldung und prüft sie. \(displayName) erfährt nicht, wer gemeldet hat.")
        }
        .task {
            if isOther { blocked = await session.isBlocked(person.userID) }
            if person.shareNow, canShare { path = ["share"] }
            name = try? await session.client.getProfile(userId: person.userID).displayName
        }
    }

    private func setBlocked(_ on: Bool) async {
        do {
            try await session.setBlocked(person.userID, on)
            blocked = on
            router.notice = on ? "\(displayName) ist blockiert." : "Blockierung von \(displayName) aufgehoben."
        } catch {
            router.notice = "Das hat nicht geklappt. Versuch es noch einmal."
        }
    }

    private func report() async {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        reason = ""
        do {
            try await session.reportUser(person.userID, reason: text)
            router.notice = "Danke. Das Team sieht sich die Meldung an."
        } catch {
            router.notice = "Die Meldung ging nicht raus. Versuch es später noch einmal."
        }
    }
}

/// Choose what to share, see who gets it and a warning, then confirm once more by name. The
/// server mails the recipient; nothing appears in the chat.
struct ContactShareView: View {
    let recipientID: String
    let recipientName: String
    @ObservedObject var session: ChatSession
    let done: () -> Void

    @State private var offer: ContactShare.Offer?
    @State private var loadError: String?
    @State private var shareEmail = false
    @State private var sharePhone = false
    @State private var phone = ""
    @State private var note = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var sendError: String?

    private var chosen: [ContactShare.Field] {
        (shareEmail ? [.email] : []) + (sharePhone ? [.phone] : [])
    }

    private var canSend: Bool {
        !chosen.isEmpty && (!sharePhone || ContactShare.isPhoneNumber(phone)) && !sending
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("An", value: recipientName)
                    .accessibilityIdentifier("contactShare.recipient")
            } footer: {
                Text("\(recipientName) bekommt eine E-Mail mit dem, was du hier auswählst. Im Chat erscheint nichts.")
            }
            if let offer, offer.member {
                Section("Was du teilst") {
                    if offer.fields.contains(.email), let email = offer.email {
                        Toggle(isOn: $shareEmail) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("E-Mail-Adresse")
                                Text(email).font(.footnote).foregroundStyle(Theme.ink3)
                            }
                        }
                        .accessibilityIdentifier("contactShare.email")
                    }
                    if offer.fields.contains(.phone) {
                        Toggle("Telefonnummer", isOn: $sharePhone)
                            .accessibilityIdentifier("contactShare.phone")
                        if sharePhone {
                            TextField("+49 170 1234567", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .accessibilityLabel("Telefonnummer")
                                .accessibilityIdentifier("contactShare.phoneNumber")
                        }
                    }
                }
                .tint(Theme.teal)
                Section("Nachricht (freiwillig)") {
                    TextField("Ein paar Worte dazu", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: note) { _, text in if text.count > 500 { note = String(text.prefix(500)) } }
                        .accessibilityIdentifier("contactShare.note")
                }
            } else if offer != nil {
                Section { Text(ContactShare.Failure.notMember.message).foregroundStyle(Theme.ink2) }
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
                Section { Text(sendError).foregroundStyle(.red).accessibilityIdentifier("contactShare.error") }
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
                .disabled(!canSend)
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
        if shareEmail, let email = offer?.email { lines.append("E-Mail: \(email)") }
        if sharePhone { lines.append("Telefon: \(phone.trimmingCharacters(in: .whitespaces))") }
        return lines.joined(separator: "\n") + "\n\n\(recipientName) kann sie danach behalten und weitergeben."
    }

    private func load() async {
        do {
            offer = try await ContactShare(session: session).offer()
        } catch {
            loadError = "Was du teilen kannst, ließ sich nicht laden. Versuch es später noch einmal."
        }
    }

    private func send() async {
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            try await ContactShare(session: session)
                .send(ContactShare.request(to: recipientID, fields: chosen, phone: phone, note: note))
            done()
        } catch let failure as ContactShare.Failure {
            sendError = failure.message
        } catch {
            sendError = ContactShare.Failure.other.message
        }
    }
}
