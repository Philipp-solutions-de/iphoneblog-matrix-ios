import SwiftUI

/// "Melden": a message or a person, with a reason. Shown from the message menu and from a profile.
struct ReportSheet: View {
    enum Subject {
        case message(roomID: String, eventID: String)
        case user(userID: String, name: String)
    }

    let subject: Subject
    let backend: ModerationBackend
    /// Called with the line to show once the report is sent.
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: Moderation.Reason = .spam
    @State private var note = ""
    @State private var sending = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Grund", selection: $reason) {
                        ForEach(Moderation.Reason.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(title)
                } footer: {
                    Text("Die Moderation von iPhoneBlog.de sieht deine Meldung, die gemeldete Nachricht und wer sie geschrieben hat. Die gemeldete Person erfährt nicht, wer gemeldet hat.")
                }
                Section("Was sollen wir wissen? (freiwillig)") {
                    TextField("Kurz beschreiben", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("report.note")
                }
                if failed {
                    Text("Das hat nicht geklappt. Versuche es gleich noch einmal.")
                        .foregroundStyle(Theme.coralText)
                }
            }
            .navigationTitle("Melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { Task { await send() } }
                        .disabled(sending)
                        .accessibilityIdentifier("report.send")
                }
            }
        }
    }

    private var title: String {
        switch subject {
        case .message: return "Warum meldest du diese Nachricht?"
        case .user(_, let name): return "Warum meldest du \(name)?"
        }
    }

    private func send() async {
        sending = true
        failed = false
        let text = Moderation.reportText(reason, note: note)
        do {
            switch subject {
            case .message(let roomID, let eventID): try await backend.reportEvent(roomID: roomID, eventID: eventID, reason: text)
            case .user(let userID, _): try await backend.reportUser(userID: userID, reason: text)
            }
            dismiss()
            done("Danke. Die Moderation schaut es sich an.")
        } catch {
            failed = true
        }
        sending = false
    }
}
