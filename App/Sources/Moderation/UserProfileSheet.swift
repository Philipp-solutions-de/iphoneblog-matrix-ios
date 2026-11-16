import SwiftUI

/// A person, opened from a name or avatar in a conversation: who it is, "Melden" and
/// "Blockieren". Blocking is Matrix's ignore list (Moderation.swift).
struct UserProfileSheet: View {
    let userID: String
    let name: String
    let ownUserID: String
    let backend: ModerationBackend
    let notice: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var blocked = false
    @State private var confirmBlock = false
    @State private var reporting = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        InitialsAvatar(name: name, size: Theme.Size.profileAvatar)
                        Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(userID).font(.system(size: 14)).foregroundStyle(Theme.ink3)
                    }
                    .padding(.vertical, 20)

                    if Moderation.canModerate(userID: userID, ownUserID: ownUserID) {
                        SettingsGroup {
                            Button { reporting = true } label: {
                                SettingsRow(label: "\(name) melden", labelColor: Theme.coralText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile.report")
                            Button {
                                if blocked { Task { await setBlocked(false) } } else { confirmBlock = true }
                            } label: {
                                SettingsRow(label: blocked ? "Blockierung aufheben" : "Blockieren", labelColor: Theme.coralText)
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                            .accessibilityIdentifier("profile.block")
                        }
                    }
                }
            }
            .background(Theme.group)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .task { blocked = (try? await backend.ignoredUsers().contains(userID)) ?? false }
        .confirmationDialog("\(name) blockieren?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Blockieren", role: .destructive) { Task { await setBlocked(true) } }
        } message: {
            Text("Du siehst keine Nachrichten von \(name) mehr, auf allen deinen Geräten. \(name) erfährt davon nichts. Aufheben kannst du das unter Ich → Blockiert.")
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(subject: .user(userID: userID, name: name), backend: backend, done: notice)
        }
    }

    private func setBlocked(_ on: Bool) async {
        busy = true
        do {
            if on { try await backend.ignore(userID: userID) } else { try await backend.unignore(userID: userID) }
            blocked = on
            notice(on ? "\(name) ist blockiert." : "\(name) ist nicht mehr blockiert.")
        } catch {
            notice("Das hat nicht geklappt. Versuche es gleich noch einmal.")
        }
        busy = false
    }
}
