import SwiftUI

/// Ich → Konto löschen (App Review Guideline 5.1.1(v)). Says what deleting means, then opens the
/// website's deletion page, where the deletion itself happens: the iphoneblog.de account is the
/// one account, and the chat account goes with it (iphoneblog-wordpress, `/konto/loeschen/`).
struct AccountDeletionView: View {
    /// The website's deletion page, opened by the caller (in the Blog's signed-in web view or a
    /// Safari sheet).
    let open: (URL) -> Void

    static func deletionURL(blogBase: URL) -> URL {
        BlogLinks.withAppView(blogBase.appending(path: "konto/loeschen/"))
    }

    let blogBase: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Konto löschen").font(Theme.Font.screenTitle).foregroundStyle(Theme.ink)
                Text("Dein Konto bei iPhoneBlog.de und dein Chat-Konto sind ein Konto. Löschen heißt:")
                    .font(Theme.Font.body).foregroundStyle(Theme.ink2)
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Dein Konto auf iphoneblog.de wird gelöscht. Du kannst dich nicht mehr anmelden.")
                    bullet("Dein Chat-Konto wird gelöscht: Name und Bild verschwinden, deine Nachrichten werden entfernt. Das ist spätestens am nächsten Morgen abgeschlossen.")
                    bullet("Ein laufendes #one-Abo endet zum Ende des bezahlten Zeitraums. Es gibt keine Erstattung und keine weitere Abbuchung.")
                    bullet("Das lässt sich nicht rückgängig machen.")
                }
                Text("Im nächsten Schritt öffnet sich die Seite auf iphoneblog.de, auf der du das Löschen bestätigst.")
                    .font(Theme.Font.footnote).foregroundStyle(Theme.ink3)
                Button { open(Self.deletionURL(blogBase: blogBase)) } label: {
                    Text("Weiter zum Löschen").frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
                }
                .buttonStyle(FilledButton(fill: Theme.coralButton))
                .accessibilityIdentifier("me.deleteAccount.continue")
            }
            .padding(Theme.Space.page)
        }
        .background(Theme.group)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink)
    }
}
