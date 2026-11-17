import SwiftUI

/// Ich's rows for App Review 1.2 and 5.1.1(v): the blocked list, the moderation contact and
/// "Konto löschen". One view, so MeView needs one line for it.
struct MeModerationRows: View {
    @EnvironmentObject private var model: AppModel
    let session: ChatSession
    @ObservedObject var router: Router
    @State private var showBlocked = false
    @State private var deleting = false

    var body: some View {
        SettingsGroup {
            LinkRow(label: "Blockiert") { showBlocked = true }
                .accessibilityIdentifier("me.blocked")
            if let address = Moderation.contactAddress, let url = URL(string: "mailto:\(address)") {
                LinkRow(label: "Moderation: \(address)", external: true) { UIApplication.shared.open(url) }
                    .accessibilityIdentifier("me.moderation")
            }
            LinkRow(label: "Konto löschen") { deleting = true }
                .accessibilityIdentifier("me.deleteAccount")
        }
        .padding(.top, 12)
        .sheet(isPresented: $showBlocked) {
            NavigationStack {
                BlockedUsersView(backend: SessionModeration(session: session))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showBlocked = false } } }
            }
        }
        .sheet(isPresented: $deleting) { AccountDeletionSheet(model: model, router: router) }
    }
}
