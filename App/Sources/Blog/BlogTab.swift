import OSLog
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
    /// One web view for the app's life (AppModel.blogWeb): switching tabs, signing in or
    /// opening a discussion never reloads the page the reader is on.
    @ObservedObject var web: BlogWebModel

    var body: some View {
        NavigationStack(path: $router.blogPath) {
            BlogHome(web: web)
                // The logo sits in the navigation bar: a bar on both the blog and the discussion
                // keeps the system back button where it belongs during a back swipe (Philip,
                // 2026-11-20). The title is what that button says; the button keeps the edge swipe.
                .navigationTitle("Blog")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Router.DiscussionRoute.self) { route in
                    DiscussionView(route: route, session: session, router: router)
                }
        }
        .onAppear {
            web.openDiscussion = { [weak router] article in router?.blogPath.append(.article(article)) }
        }
        // Signed in: the web view gets the member's WordPress session (#one articles open);
        // signed out: WordPress's cookies go too.
        .task(id: session?.userID) {
            web.setMember(session.map { session in
                BlogWebModel.Member(userID: session.userID,
                                    token: { try? session.client.session().accessToken },
                                    refresh: { _ = try? await session.client.displayName() })
            })
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

/// The logo bar on top (preview "Blog tab"), the blog below, and what shows while it loads
/// or when it cannot.
private struct BlogHome: View {
    @ObservedObject var web: BlogWebModel

    var body: some View {
        BlogWebView(model: web)
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.background)
            .overlay {
                switch web.phase {
                case .loading:
                    ProgressView()
                case .failed:
                    ContentUnavailableView {
                        Label("Blog nicht erreichbar", systemImage: "wifi.slash")
                    } description: {
                        Text("Die Seite lässt sich gerade nicht laden.")
                    } actions: {
                        Button("Nochmal versuchen") { web.retry() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.teal)
                    }
                    .background(Theme.background)
                case .ready:
                    EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { web.goHome() } label: {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: Theme.BlogBar.logo, height: Theme.BlogBar.logo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("iPhoneBlog.de, zum Anfang")
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// The values of the logo bar. Theme.swift belongs to the navigation shell; these move there
/// when it next changes.
extension Theme {
    enum BlogBar {
        static let logo: CGFloat = 34
    }
}

/// The Blog tab's web view and its state: the page keeps the app view, hands discussions to
/// the app and sends everything else to Safari.
@MainActor
final class BlogWebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum Phase: Equatable { case loading, ready, failed }

    /// `loading` and `failed` cover the page only until the first page showed; after that a
    /// failed load keeps what the reader sees.
    @Published private(set) var phase: Phase = .loading
    let start: URL
    let webView: WKWebView
    /// A tap on "Diskussion": the article's permalink.
    var openDiscussion: ((URL) -> Void)?

    /// The signed-in person, for WordPress's web login (BlogWebLogin.swift).
    struct Member {
        let userID: String
        /// The current Matrix access token.
        let token: () async -> String?
        /// Makes the SDK refresh an expired token (any authenticated call does).
        let refresh: () async -> Void
    }

    private var member: Member?
    /// Asked once per app start and person; a used or expired link may ask once more.
    private var webLoginDone: String?
    private var webLoginRunning = false
    private var webLoginRetries = 0
    private let log = Logger(subsystem: Brand.bundleID, category: "blog")

    init(start: URL) {
        self.start = start
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
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
        refresh.addTarget(self, action: #selector(pulled(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        #if DEBUG && targetEnvironment(simulator)
        if TestGate.cookie() != nil {
            // Set before the first request, or the first page meets the gate (TestGate.swift).
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await TestGate.install(in: configuration.websiteDataStore) { log.info("beta test gate cookie set") }
                webView.load(URLRequest(url: start))
            }
            return
        }
        #endif
        webView.load(URLRequest(url: start))
    }


    func retry() {
        phase = .loading
        if webView.url == nil { webView.load(URLRequest(url: start)) } else { webView.reload() }
    }

    /// A tap on the logo: the start page, or its top when already there.
    func goHome() {
        if let url = webView.url, BlogLinks.withAppView(url) == BlogLinks.withAppView(start) {
            webView.scrollView.setContentOffset(CGPoint(x: 0, y: -webView.scrollView.adjustedContentInset.top), animated: true)
        } else {
            webView.load(URLRequest(url: start))
        }
    }

    /// An article, from "Artikel lesen".
    func open(_ article: URL) {
        let target = BlogLinks.withAppView(article)
        if let url = webView.url, DiscussionStore.key(for: url) == DiscussionStore.key(for: target) { return }
        webView.load(URLRequest(url: target))
    }

    @objc private func pulled(_ control: UIRefreshControl) {
        // Ends when the page has loaded (didFinish/didFail), not at once.
        if webView.url == nil { webView.load(URLRequest(url: start)) } else { webView.reload() }
    }

    private func finished(failed: Bool) {
        webView.scrollView.refreshControl?.endRefreshing()
        if !failed { phase = .ready } else if phase != .ready { phase = .failed }
        if !failed { Task { await webLoginIfNeeded() } }
    }

    // MARK: WordPress session for members

    func setMember(_ new: Member?) {
        let before = member?.userID
        member = new
        guard new?.userID != before else { return }
        webLoginDone = nil
        webLoginRetries = 0
        if new == nil, before != nil {
            Task { await removeWordPressCookies() }
        } else if phase == .ready {
            Task { await webLoginIfNeeded() }
        }
    }

    /// POST web-login from the page (same origin, past beta's gate), then open the one-time
    /// address it returns. Only from a blog page: on the gate's sign-in page it waits.
    private func webLoginIfNeeded() async {
        guard let member, webLoginDone != member.userID, !webLoginRunning,
              let page = webView.url, let host = page.host()?.lowercased(),
              BlogLinks.blogHosts.contains(host) || host == start.host()?.lowercased(),
              !page.path().hasPrefix("/chat/web-login") else { return }
        webLoginRunning = true
        defer { webLoginRunning = false }
        for attempt in 0..<2 {
            guard let token = await member.token() else { return }
            let answer: Any?
            do {
                answer = try await webView.callAsyncJavaScript(
                    WebLogin.script,
                    arguments: ["path": WebLogin.path, "token": token, "weiter": WebLogin.weiter(for: page)],
                    in: nil, contentWorld: .defaultClient)
            } catch {
                log.error("web login: \(error.localizedDescription, privacy: .public)")
                webLoginDone = member.userID
                return
            }
            let result = answer as? [String: Any]
            let status = (result?["status"] as? NSNumber)?.intValue ?? 0
            switch WebLogin.outcome(status: status, body: result?["body"] as? String ?? "", pageHost: host) {
            case .open(let url):
                webLoginDone = member.userID
                webView.load(URLRequest(url: url))
                return
            case .refreshToken where attempt == 0:
                await member.refresh()
            case .refreshToken:
                log.error("web login: token refused twice")
                webLoginDone = member.userID
                return
            case .stop(let reason):
                log.info("web login: \(reason, privacy: .public)")
                webLoginDone = member.userID
                return
            }
        }
    }

    private func removeWordPressCookies() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in await store.allCookies() where WordPressCookies.isWordPress(cookie) {
            await store.deleteCookie(cookie)
        }
        webView.reload()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        // Taps are routed below. Everything else (redirects, a page's script, reloads, frames) may
        // show only the blog in the main frame; anything off it opens in Safari, so the app does
        // not count as unrestricted web access in the age rating (BlogURLPolicy).
        guard action.navigationType == .linkActivated || url.scheme == "iphoneblog-chat" else {
            switch BlogURLPolicy.decide(url, mainFrame: action.targetFrame?.isMainFrame ?? true, blogHost: start.host()) {
            case .allow: return decisionHandler(.allow)
            case .cancel: return decisionHandler(.cancel)
            case .openOutside:
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
                return
            }
        }
        switch BlogLinks.classify(url, blogHost: start.host()) {
        case .discussion(let article):
            decisionHandler(.cancel)
            openDiscussion?(article)
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
            decisionHandler(url.scheme == "iphoneblog-chat" ? .cancel : .allow)
        }
    }

    /// A used or expired one-time link answers 410: stay on the page and ask for a new one, once.
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let http = response.response as? HTTPURLResponse, http.statusCode == 410,
              http.url?.path().hasPrefix("/chat/web-login") == true else { return .allow }
        if webLoginRetries < 1 {
            webLoginRetries += 1
            webLoginDone = nil
            Task { await webLoginIfNeeded() }
        }
        return .cancel
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

    /// iOS ends a web view's content process under memory pressure; the page would stay blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// A load the app replaced itself (app=1, Diskussion) is not a failure.
    private static func isCancel(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102) // frame load interrupted
    }

    // MARK: WKUIDelegate

    /// `target="_blank"` links: same rules, never a second web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            switch BlogLinks.classify(url, blogHost: start.host()) {
            case .discussion(let article): openDiscussion?(article)
            case .blog(let keeping): webView.load(URLRequest(url: keeping ?? url))
            case .external: UIApplication.shared.open(url)
            case .ignore: break
            }
        }
        return nil
    }
}

/// The web view in SwiftUI; the model owns it.
struct BlogWebView: UIViewRepresentable {
    let model: BlogWebModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ view: WKWebView, context: Context) { }
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

    /// The same address with `app=1`, once.
    static func withAppView(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "app" } + [URLQueryItem(name: "app", value: "1")]
        return components.url ?? url
    }

    static func classify(_ url: URL, blogHost: String?) -> Target {
        switch url.scheme?.lowercased() {
        case "iphoneblog-chat":
            guard url.host() == "diskussion",
                  let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value,
                  let article = URL(string: raw), ["http", "https"].contains(article.scheme?.lowercased() ?? ""),
                  article.host() != nil else { return .ignore }
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
