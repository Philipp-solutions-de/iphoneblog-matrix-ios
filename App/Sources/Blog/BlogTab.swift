import SwiftUI
import WebKit

/// The Blog tab: the blog itself as WordPress's app view (`?app=1`: no banner, header, menu,
/// footer; a "Diskussion" link under each article). A tap on that link opens the article's
/// discussion natively, with Back. Links that leave the blog open in Safari.
/// 2026-11-14_interfaces.md, "Blog app view (WordPress PR #274)".
struct BlogTab: View {
    @ObservedObject var router: Router
    /// Nil while signed out.
    let session: ChatSession?

    var body: some View {
        NavigationStack(path: $router.blogPath) {
            BlogWebView(start: Self.startURL) { article in
                router.blogPath.append(.article(article))
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Router.DiscussionRoute.self) { route in
                DiscussionView(route: route, session: session, router: router)
            }
        }
    }

    /// beta.iphoneblog.de while the app view is tested, www once it is live (brand.env).
    static var startURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["IPHONEBLOG_BLOG_WEB"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: Brand.blogWebURL)! // swiftlint:disable:this force_unwrapping
    }
}

/// A WKWebView on the blog that keeps the app view, hands discussions to the app and sends
/// everything else to Safari.
struct BlogWebView: UIViewRepresentable {
    let start: URL
    let openDiscussion: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(start: start, openDiscussion: openDiscussion) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = UIColor(Theme.background)
        view.scrollView.backgroundColor = UIColor(Theme.background)
        view.customUserAgent = nil
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        view.scrollView.refreshControl = refresh
        context.coordinator.webView = view
        view.load(URLRequest(url: start))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) { }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let start: URL
        let openDiscussion: (URL) -> Void
        weak var webView: WKWebView?

        init(start: URL, openDiscussion: @escaping (URL) -> Void) {
            self.start = start
            self.openDiscussion = openDiscussion
        }

        @objc func reload(_ sender: UIRefreshControl) {
            webView?.reload()
            sender.endRefreshing()
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            // Only taps are routed. Redirects, reloads and the page's own loads (a sign-in gate,
            // an embedded player) go where the server sends them.
            guard action.navigationType == .linkActivated || url.scheme == "iphoneblog-chat" else {
                return decisionHandler(url.scheme == "http" || url.scheme == "https" || url.scheme == "about" ? .allow : .cancel)
            }
            switch BlogLinks.classify(url, blogHost: start.host()) {
            case .discussion(let article):
                decisionHandler(.cancel)
                openDiscussion(article)
            case .blog(let keepingAppView):
                if let keepingAppView, action.targetFrame?.isMainFrame ?? true {
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: keepingAppView))
                } else {
                    decisionHandler(.allow)
                }
            case .external:
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            case .ignore:
                decisionHandler(.allow)
            }
        }

        /// `target="_blank"` links: same rules, never a second web view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                switch BlogLinks.classify(url, blogHost: start.host()) {
                case .discussion(let article): openDiscussion(article)
                case .blog(let keeping): webView.load(URLRequest(url: keeping ?? url))
                case .external: UIApplication.shared.open(url)
                case .ignore: break
                }
            }
            return nil
        }
    }
}

/// Where a link in the blog leads. Pure, so it is tested without a web view.
enum BlogLinks {
    enum Target: Equatable {
        /// `iphoneblog-chat://diskussion?url=<permalink>`: the article's discussion.
        case discussion(URL)
        /// A page of the blog; non-nil when app=1 must be added to keep the app view.
        case blog(keepingAppView: URL?)
        /// Anywhere else: Safari.
        case external
        /// about:blank, data: and the like, which the page loads for itself.
        case ignore
    }

    static let blogHosts: Set<String> = ["www.iphoneblog.de", "iphoneblog.de", "beta.iphoneblog.de"]

    static func classify(_ url: URL, blogHost: String?) -> Target {
        switch url.scheme?.lowercased() {
        case "iphoneblog-chat":
            guard url.host() == "diskussion",
                  let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value,
                  let article = URL(string: raw) else { return .ignore }
            return .discussion(article)
        case "http", "https":
            guard let host = url.host()?.lowercased(),
                  blogHosts.contains(host) || host == blogHost?.lowercased() else { return .external }
            // Downloads and feeds are not pages; the blog's pages keep app=1.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let items = components?.queryItems ?? []
            if items.contains(where: { $0.name == "app" && $0.value == "1" }) { return .blog(keepingAppView: nil) }
            components?.queryItems = items + [URLQueryItem(name: "app", value: "1")]
            return .blog(keepingAppView: components?.url)
        case "mailto", "tel":
            return .external
        default:
            return .ignore
        }
    }
}
