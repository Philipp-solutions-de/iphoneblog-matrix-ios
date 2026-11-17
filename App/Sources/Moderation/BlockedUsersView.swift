import SwiftUI

/// Ich → Blockiert: everybody on this account's ignore list, each with "Aufheben".
struct BlockedUsersView: View {
    let backend: ModerationBackend
    @State private var users: [String]?
    @State private var failed = false

    var body: some View {
        List {
            if let users, users.isEmpty {
                Text("Du hast niemanden blockiert.").foregroundStyle(Theme.ink3)
            }
            ForEach(users ?? [], id: \.self) { userID in
                HStack {
                    Text(userID).foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Aufheben") { Task { await unblock(userID) } }
                        .foregroundStyle(Theme.teal)
                }
            }
            if failed {
                Text("Die Liste ließ sich nicht laden.").foregroundStyle(Theme.coralText)
            }
        }
        .navigationTitle("Blockiert")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { users = try await backend.ignoredUsers().sorted(); failed = false } catch { failed = true }
    }

    private func unblock(_ userID: String) async {
        do { try await backend.unignore(userID: userID); await load() } catch { failed = true }
    }
}
