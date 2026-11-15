import Foundation
import WebKit

/// Signs the Blog tab's web view in to WordPress for a signed-in member, so #one articles
/// open (iphoneblog-wordpress PR #276, `POST /wp-json/iphoneblog/v1/chat/web-login`).
///
/// The request runs as `fetch` inside the web view, not through URLSession: on beta it must
/// pass the staff gate, whose cookie only the web view holds. It runs in its own JavaScript
/// world, so the blog's scripts (and anything they load) never see the Matrix token, and only
/// from a page on a blog host. The answer is a one-time address on the same host, valid 60 s,
/// that sets the WordPress cookie and redirects to the page the reader is on.
enum WebLogin {
    static let path = "/wp-json/iphoneblog/v1/chat/web-login"

    /// What to do with WordPress's answer.
    enum Outcome: Equatable {
        /// Load this address once, now.
        case open(URL)
        /// 401: the token is not (or no longer) active. Refresh it and ask once more.
        case refreshToken
        /// Anything else: no member session this time; the reason for the log.
        case stop(String)
    }

    static func outcome(status: Int, body: String, pageHost: String) -> Outcome {
        switch status {
        case 200:
            guard let data = body.data(using: .utf8),
                  let answer = try? JSONDecoder().decode(Answer.self, from: data),
                  let url = URL(string: answer.url) else { return .stop("200 without a url") }
            // Only WordPress's own one-time page on the host we asked.
            guard url.scheme == "https", url.host()?.lowercased() == pageHost.lowercased(),
                  url.path().hasPrefix("/chat/web-login") else { return .stop("unexpected address") }
            return .open(url)
        case 401:
            return .refreshToken
        default:
            let code = (body.data(using: .utf8)).flatMap { try? JSONDecoder().decode(Failure.self, from: $0) }?.code
            return .stop("\(status) \(code ?? "-")")
        }
    }

    /// `weiter`: where WordPress sends the reader after signing in: the page they are on,
    /// as a path on the blog without the host. The app view's flag is WordPress's to add.
    static func weiter(for page: URL?) -> String {
        guard let page else { return "/" }
        let path = page.path(percentEncoded: true)
        return path.isEmpty ? "/" : path
    }

    /// Runs in `WKContentWorld.defaultClient`: the page's own `fetch` cannot be replaced there.
    static let script = """
    const response = await fetch(path, {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
        body: JSON.stringify({ weiter: weiter })
    });
    return { status: response.status, body: await response.text() };
    """

    private struct Answer: Decodable {
        let url: String
    }

    private struct Failure: Decodable {
        let code: String?
    }
}

/// WordPress's cookies, removed when the person signs out of the app.
enum WordPressCookies {
    static func isWordPress(_ cookie: HTTPCookie) -> Bool {
        cookie.name.hasPrefix("wordpress_") || cookie.name.hasPrefix("wp-settings")
    }
}
