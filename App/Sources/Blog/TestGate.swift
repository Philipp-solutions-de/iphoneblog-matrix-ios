#if DEBUG && targetEnvironment(simulator)
import OSLog
import SwiftUI
import WebKit

/// Beta's staff gate for a simulator on Thorsten's Mac. The gate lets a request past with the
/// machine token (infra docs/staff-gate.md, "A token for machines"); edge also takes it as the
/// cookie `test_gate`, on beta only. It opens the door and buys nothing behind it: no staff
/// session, so a member still signs in with their own password and staff still need a passkey.
///
/// A cookie, not the X-Test-Gate header: WKWebView adds headers to the pages it is told to
/// load, not to their styles, scripts and fetches, and the gate covers every path. Only a Debug
/// build in the simulator compiles this, and the token stays on the Mac
/// ($SIMULATOR_HOST_HOME/.config/iphoneblog/test-gate-beta, README "Beta in the simulator"),
/// so nothing ships in the app. scripts/check-release-clean.sh fails an App Store build that
/// carries it.
enum TestGate {
    /// The cookie, host-only for beta.iphoneblog.de; nil without the token file.
    static func cookie() -> HTTPCookie? {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
              let raw = try? String(contentsOfFile: home + "/.config/iphoneblog/test-gate-beta", encoding: .utf8) else {
            return nil
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 32 else { return nil }
        return HTTPCookie(properties: [
            .name: "test_gate", .value: token, .domain: "beta.iphoneblog.de", .path: "/",
            .secure: "TRUE", .expires: Date().addingTimeInterval(7 * 86_400),
        ])
    }

    /// Puts the cookie into the shared web data store (the Blog tab and the sign-in sheet).
    @MainActor static func install(in store: WKWebsiteDataStore) async -> Bool {
        guard let cookie = cookie() else { return false }
        await store.httpCookieStore.setCookie(cookie)
        return true
    }
}

/// The chat sign-in in a web view that carries the gate cookie, for the simulator only. The
/// system's sign-in sheet (ASWebAuthenticationSession) keeps Safari's cookies, so on beta it met
/// Authelia, whose passkey the simulator lacks. This sheet catches the app's callback
/// (de.iphoneblog.chat:/oauth/callback) itself and logs each hop as host and path only, never a
/// query (codes, states and tokens live there).
struct WebSignInSheet: UIViewRepresentable {
    let url: URL
    let callbackScheme: String
    let finish: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(callbackScheme: callbackScheme, finish: finish) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true
        Task { @MainActor in
            _ = await TestGate.install(in: configuration.websiteDataStore)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let callbackScheme: String
        let finish: (URL?) -> Void
        private var done = false
        private let log = Logger(subsystem: Brand.bundleID, category: "signin-web")

        init(callbackScheme: String, finish: @escaping (URL?) -> Void) {
            self.callbackScheme = callbackScheme
            self.finish = finish
        }

        private static func hop(_ url: URL?) -> String {
            guard let url else { return "-" }
            return "\(url.scheme ?? "")://\(url.host() ?? "")\(url.path())"
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            let url = action.request.url
            log.info("go \(Self.hop(url), privacy: .public)")
            if url?.scheme == callbackScheme, !done {
                done = true
                log.info("callback caught")
                finish(url)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            log.info("redirect \(Self.hop(webView.url), privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            log.info("shown \(Self.hop(webView.url), privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // The callback's custom scheme ends in a cancelled load; that is the way out, not a failure.
            guard !done else { return }
            log.error("failed \(Self.hop(webView.url), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
