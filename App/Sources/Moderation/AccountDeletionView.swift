import SwiftUI
import WebKit

/// "Konto löschen" (App Review Guideline 5.1.1(v)). Says what deleting means, then opens the
/// website's deletion page inside the app, where the deletion itself happens: the iphoneblog.de
/// account is the one account, and the chat account goes with it (iphoneblog-wordpress,
/// `/konto/loeschen/`). Once the page says the account is gone, the app signs out on this device:
/// the chat token would otherwise live until the server's nightly erase.
struct AccountDeletionView: View {
    /// The blog's address; the page is on the same host.
    let blogBase: URL
    /// Called once the website confirms the deletion.
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPage = false

    static func deletionURL(blogBase: URL) -> URL {
        BlogLinks.withAppView(blogBase.appending(path: "konto/loeschen/"))
    }

    /// The page WordPress shows after deleting: `/konto/loeschen/?geloescht=1`.
    static func isDeletedPage(_ url: URL) -> Bool {
        let path = url.path()
        guard path == "/konto/loeschen/" || path == "/konto/loeschen" else { return false }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "geloescht" && $0.value == "1" }) ?? false
    }

    var body: some View {
        Group {
            if showPage {
                DeletionWebView(url: Self.deletionURL(blogBase: blogBase), blogHost: blogBase.host()) {
                    onDeleted()
                    dismiss()
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                explanation
            }
        }
        .navigationTitle("Konto löschen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
    }

    private var explanation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
                Button { showPage = true } label: {
                    Text("Weiter zum Löschen").frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
                }
                .buttonStyle(FilledButton(fill: Theme.coralButton))
                .accessibilityIdentifier("me.deleteAccount.continue")
            }
            .padding(Theme.Space.page)
        }
        .background(Theme.group)
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

/// The deletion page in a web view that shares the Blog tab's cookies (the default data store), so
/// a member signed in there is signed in here. It stays on the blog like the Blog tab
/// (BlogURLPolicy) and reports the confirmation page.
private struct DeletionWebView: UIViewRepresentable {
    let url: URL
    let blogHost: String?
    let deleted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(blogHost: blogHost, deleted: deleted) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let blogHost: String?
        let deleted: () -> Void
        private var reported = false

        init(blogHost: String?, deleted: @escaping () -> Void) {
            self.blogHost = blogHost
            self.deleted = deleted
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            switch BlogURLPolicy.decide(url, mainFrame: action.targetFrame?.isMainFrame ?? true, blogHost: blogHost) {
            case .allow: decisionHandler(.allow)
            case .cancel: decisionHandler(.cancel)
            case .openOutside:
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !reported, let url = webView.url, AccountDeletionView.isDeletedPage(url) else { return }
            reported = true
            // Let the person read "Dein Konto ist gelöscht" for a moment before the app signs out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [deleted] in deleted() }
        }
    }
}

/// "Konto löschen" as a sheet, from #one-Chat's members-only screen and from Ich. After the
/// deletion the app signs out on this device and says so.
struct AccountDeletionSheet: View {
    let model: AppModel
    let router: Router

    /// The blog's own host, from the Blog tab's start address.
    static var blogBase: URL { URL(string: "/", relativeTo: BlogTab.startURL)?.absoluteURL ?? BlogTab.startURL }

    var body: some View {
        NavigationStack {
            AccountDeletionView(blogBase: Self.blogBase) {
                Task {
                    await model.signOut()
                    router.notice = "Dein Konto ist gelöscht."
                }
            }
        }
    }
}
