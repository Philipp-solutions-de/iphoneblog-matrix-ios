import SwiftUI
import UIKit
import WebKit

/// The Blog tab's web view and its state. One per app: it lives across tab switches and
/// sign-in, so the reader comes back to where they were.
@MainActor
final class BlogWebModel: NSObject, ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    /// The page's title, for the Diskussion view when the thread is not found.
    @Published private(set) var pageTitle: String?

    let webView: WKWebView
    let home: URL
    private let hosts: Set<String>
    /// The "Diskussion" link was tapped: the article's permalink.
    var onDiscussion: ((URL) -> Void)?

    init(home: URL = BlogWeb.home) {
        self.home = home
        hosts = BlogWeb.blogHosts(home: home)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        // Page colour behind and under the page: no white flash in dark mode.
        let background = UIColor(Theme.background)
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.underPageBackgroundColor = background
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulledToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        webView.load(URLRequest(url: home))
    }

    /// Reload the current page, or the start page after a failed first load.
    func reload() {
        phase = .loading
        if webView.url == nil {
            webView.load(URLRequest(url: home))
        } else {
            webView.reload()
        }
    }

    /// The start page, scrolled to the top (a tap on the logo).
    func goHome() {
        if webView.url.map(AppFlag.added(to:)) == AppFlag.added(to: home) {
            webView.scrollView.setContentOffset(CGPoint(x: 0, y: -webView.scrollView.adjustedContentInset.top), animated: true)
        } else {
            webView.load(URLRequest(url: home))
        }
    }

    /// An article, from "Artikel lesen" in the Diskussion view.
    func open(_ article: URL) {
        let target = AppFlag.added(to: article)
        if let current = webView.url, ArticlePath.key(current) == ArticlePath.key(target) { return }
        webView.load(URLRequest(url: target))
    }

    @objc private func pulledToRefresh(_ control: UIRefreshControl) {
        if webView.url == nil { webView.load(URLRequest(url: home)) } else { webView.reload() }
    }

    private func finished(failed: Bool) {
        webView.scrollView.refreshControl?.endRefreshing()
        pageTitle = webView.title
        if failed {
            // A failed reload over a page already shown keeps that page.
            if phase != .ready { phase = .failed }
        } else {
            phase = .ready
        }
    }

    /// Mail, phone, other websites: Safari and friends, not this view.
    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }

    fileprivate func handle(_ decision: BlogNavigation) -> WKNavigationActionPolicy {
        switch decision {
        case .allow:
            return .allow
        case .reload(let url):
            webView.load(URLRequest(url: url))
            return .cancel
        case .discussion(let permalink):
            onDiscussion?(permalink)
            return .cancel
        case .external(let url):
            openExternally(url)
            return .cancel
        case .ignore:
            return .cancel
        }
    }
}

extension BlogWebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        // A link with target="_blank" has no target frame; treat it as the main frame.
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        return handle(BlogNavigation.decide(url, mainFrame: mainFrame, blogHosts: hosts))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView.url == nil { phase = .loading }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished(failed: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished(failed: !Self.isCancel(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finished(failed: !Self.isCancel(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// A navigation the app cancelled itself (reload with app=1, Diskussion) is not a failure.
    private static func isCancel(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102) // frame load interrupted
    }
}

extension BlogWebModel: WKUIDelegate {
    /// `target="_blank"` and `window.open`: blog pages load here, the rest goes to Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, handle(BlogNavigation.decide(url, mainFrame: true, blogHosts: hosts)) == .allow {
            webView.load(action.request)
        }
        return nil
    }
}

/// The web view in SwiftUI.
struct BlogWebView: UIViewRepresentable {
    let model: BlogWebModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ view: WKWebView, context: Context) { }
}
