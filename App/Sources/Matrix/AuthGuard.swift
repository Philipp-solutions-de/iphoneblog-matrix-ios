import Foundation

/// Decides whether a token error really ends the session (Alex: repeated logouts on days the
/// server was redeployed). A token error alone is no proof: MAS's access tokens live minutes,
/// our own HTTP calls do not refresh them, and when the SDK's refresh hits a restarting MAS
/// (502, 503, reset, timeout) it reports the same "unknown token" as a revoked session.
///
/// So a suspicion is checked: the SDK makes one authenticated request (refreshing the token on
/// the way), then the server is asked directly. The session ends only on a definite answer:
/// MAS refused the refresh token (invalid_grant), or the server keeps refusing the token
/// (401 M_UNKNOWN_TOKEN, soft_logout false) while MAS answers, three times in a row. Anything
/// else is the server being away: the app keeps the session and checks again with backoff.
@MainActor
final class AuthGuard {
    enum Verdict: Equatable {
        /// The token works (after a refresh, if one was due).
        case valid
        /// MAS or the homeserver did not answer properly: keep the session, try again later.
        case unreachable
        /// The server refused the token while MAS answered; not yet proof on its own.
        case refused
        /// MAS refused the refresh token: the session is over.
        case invalid
    }

    struct Probes {
        /// One authenticated SDK request; nil on success, else the error's description.
        var sdkRequest: () async -> String?
        /// GET /account/whoami with the current token: status and body, nil when unreachable.
        var whoami: () async -> (status: Int, body: Data)?
        /// Whether MAS answers at all (its discovery document).
        var issuerUp: () async -> Bool
        var sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    private let probes: Probes
    /// Ends the session; the argument says why ("invalid_grant" or "refused").
    private let signOut: (String) -> Void
    /// Tells home what happened, without anything about the person (MetricsReporter).
    private let report: ([String: String]) -> Void
    /// Where the suspicion came from: "sdk" or the shape of our own call's path, and its errcode.
    private var trigger = ("", "")
    private var checking: Task<Void, Never>?
    /// The check in progress: every caller awaits the same one, so two token errors at once
    /// lead to one SDK request and so at most one refresh.
    private var inFlight: Task<Verdict, Never>?
    /// When the SDK last saved refreshed tokens (KeychainSessionDelegate). A 401 for a request
    /// sent before it, and refusals counted before it, say nothing about the new token.
    private(set) var lastRefresh = Date.distantPast
    /// Seconds between checks while the server is away: 2, 4, 8 … 60.
    static let backoff: [Int] = [2, 4, 8, 16, 32, 60]
    /// How many refusals in a row, with MAS answering, end the session.
    static let refusalsToSignOut = 3

    init(probes: Probes, report: @escaping ([String: String]) -> Void = { _ in }, signOut: @escaping (String) -> Void) {
        self.probes = probes
        self.report = report
        self.signOut = signOut
    }

    /// One check, as the order above describes; joins the one in progress, if any.
    func check() async -> Verdict {
        if let inFlight { return await inFlight.value }
        let task = Task { await checkOnce() }
        inFlight = task
        let verdict = await task.value
        inFlight = nil
        return verdict
    }

    /// The SDK saved a refreshed pair.
    func noteRefresh(at date: Date = .now) {
        lastRefresh = date
    }

    private func checkOnce() async -> Verdict {
        guard let sdkError = await probes.sdkRequest() else { return .valid }
        if sdkError.contains("invalid_grant") { return .invalid }
        guard let (status, body) = await probes.whoami() else { return .unreachable }
        if (200..<300).contains(status) { return .valid }
        guard status == 401, Self.isHardUnknownToken(body) else { return .unreachable }
        return await probes.issuerUp() ? .refused : .unreachable
    }

    /// Something reported a token error: check, and keep checking with backoff until the
    /// token works or the session is definitely over. One check at a time.
    func suspect(from source: String = "sdk", errcode: String = "M_UNKNOWN_TOKEN", requestSent: Date = .now) {
        // An answer to a request made with the previous token: the new one has not failed.
        guard requestSent >= lastRefresh, checking == nil else { return }
        trigger = (source, errcode)
        checking = Task { [weak self] in
            await self?.run()
            self?.checking = nil
        }
    }

    /// For our own calls: true when the token works now (refreshed), so the call may be retried.
    func confirmValid(path: String, requestSent: Date) async -> Bool {
        if requestSent < lastRefresh { return true }
        if await check() == .valid { return true }
        suspect(from: Self.shape(of: path), requestSent: requestSent)
        return false
    }

    /// A path with every ID replaced: "/_matrix/client/v3/rooms/*/event/*".
    nonisolated static func shape(of path: String) -> String {
        let bare = path.split(separator: "?").first.map(String.init) ?? path
        return bare.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            segment.contains(where: { "@!$#%:".contains($0) }) ? "*" : String(segment)
        }.joined(separator: "/")
    }

    /// The check loop behind `suspect()`; internal for the tests.
    func run() async {
        var refusals = 0
        var attempt = 0
        while !Task.isCancelled {
            let refreshBefore = lastRefresh
            let verdict = await check()
            // A refresh during or since the last checks: what was refused was the old token.
            if lastRefresh != refreshBefore { refusals = 0 }
            switch verdict {
            case .valid:
                // Only worth a line when it took more than the first check.
                if attempt > 0 { breadcrumb("kept", checks: attempt + 1) }
                return
            case .invalid:
                breadcrumb("signout_invalid_grant", checks: attempt + 1)
                signOut("invalid_grant")
                return
            case .refused where lastRefresh != refreshBefore:
                refusals = 0
            case .refused:
                refusals += 1
                if refusals >= Self.refusalsToSignOut {
                    breadcrumb("signout_refused", checks: attempt + 1)
                    signOut("refused")
                    return
                }
            case .unreachable:
                refusals = 0
            }
            await probes.sleep(.seconds(Self.backoff[min(attempt, Self.backoff.count - 1)]))
            attempt += 1
        }
    }

    private func breadcrumb(_ outcome: String, checks: Int) {
        report(["ev": "auth", "out": outcome, "from": trigger.0, "err": trigger.1, "n": "\(checks)"])
    }

    func cancel() {
        checking?.cancel()
        checking = nil
    }

    /// 401 M_UNKNOWN_TOKEN without soft_logout: true. A soft logout means "refresh and go on".
    nonisolated static func isHardUnknownToken(_ body: Data) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return false }
        return json["errcode"] as? String == "M_UNKNOWN_TOKEN" && json["soft_logout"] as? Bool != true
    }
}
