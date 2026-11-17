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
    private let signOut: () -> Void
    private var checking: Task<Void, Never>?
    /// Seconds between checks while the server is away: 2, 4, 8 … 60.
    static let backoff: [Int] = [2, 4, 8, 16, 32, 60]
    /// How many refusals in a row, with MAS answering, end the session.
    static let refusalsToSignOut = 3

    init(probes: Probes, signOut: @escaping () -> Void) {
        self.probes = probes
        self.signOut = signOut
    }

    /// One check, as the order above describes.
    func check() async -> Verdict {
        guard let sdkError = await probes.sdkRequest() else { return .valid }
        if sdkError.contains("invalid_grant") { return .invalid }
        guard let (status, body) = await probes.whoami() else { return .unreachable }
        if (200..<300).contains(status) { return .valid }
        guard status == 401, Self.isHardUnknownToken(body) else { return .unreachable }
        return await probes.issuerUp() ? .refused : .unreachable
    }

    /// Something reported a token error: check, and keep checking with backoff until the
    /// token works or the session is definitely over. One check at a time.
    func suspect() {
        guard checking == nil else { return }
        checking = Task { [weak self] in
            await self?.run()
            self?.checking = nil
        }
    }

    /// For our own calls: true when the token works now (refreshed), so the call may be retried.
    func confirmValid() async -> Bool {
        if await check() == .valid { return true }
        suspect()
        return false
    }

    /// The check loop behind `suspect()`; internal for the tests.
    func run() async {
        var refusals = 0
        var attempt = 0
        while !Task.isCancelled {
            switch await check() {
            case .valid:
                return
            case .invalid:
                signOut()
                return
            case .refused:
                refusals += 1
                if refusals >= Self.refusalsToSignOut {
                    signOut()
                    return
                }
            case .unreachable:
                refusals = 0
            }
            await probes.sleep(.seconds(Self.backoff[min(attempt, Self.backoff.count - 1)]))
            attempt += 1
        }
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
