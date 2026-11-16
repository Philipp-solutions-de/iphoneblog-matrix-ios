import Foundation

/// Which address the Blog tab's web view may show itself, for every navigation that is not a tap
/// (taps go through `BlogLinks.classify`): redirects, a page's script changing `location`, reloads
/// and frames.
///
/// **The web view never leaves iphoneblog.de in its main frame.** App Review counts an app whose
/// web view goes anywhere as "unrestricted web access" and rates it 16+ (App Store Connect's age
/// rating questions); a blog app should get 13+. So a redirect or script that leads off the blog
/// opens Safari instead, as a tap on an outside link already does. Frames inside a blog page
/// (an embedded player) may load from elsewhere: they stay inside the article.
///
/// Beta's staff gate (`auth.phso.de`) is the one outside host the main frame may show, and only
/// while the app points at beta: without it nobody gets past the gate to the blog.
enum BlogURLPolicy {
    enum Decision: Equatable {
        case allow
        /// Off the blog: cancel here and open in Safari.
        case openOutside
        /// A scheme the web view has no business loading.
        case cancel
    }

    static let liveHosts: Set<String> = ["www.iphoneblog.de", "iphoneblog.de"]
    static let staffGateHosts: Set<String> = ["auth.phso.de"]

    static func decide(_ url: URL, mainFrame: Bool, blogHost: String?) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            // A page's own blank frames and generated media; never a place to browse to.
            return mainFrame && scheme != "about" ? .cancel : .allow
        }
        guard scheme == "http" || scheme == "https" else { return .cancel }
        guard mainFrame else { return .allow }
        guard let host = url.host()?.lowercased() else { return .cancel }
        let blog = blogHost?.lowercased()
        if BlogLinks.blogHosts.contains(host) || host == blog { return .allow }
        let onBeta = blog.map { !liveHosts.contains($0) } ?? false
        if onBeta, staffGateHosts.contains(host) { return .allow }
        return .openOutside
    }
}
