import Foundation
import MatrixRustSDK
import OSLog

/// The app's top-level state: signed out, or signed in with one `ChatSession`.
@MainActor
final class AppModel: ObservableObject {
    enum State {
        case starting
        case signedOut
        case signingIn
        case signedIn(ChatSession)
    }

    @Published private(set) var state: State = .starting
    /// Navigation lives here, not in the session: the Blog tab exists signed out too.
    let router = Router()
    @Published var errorMessage: String?
    /// True when the server offers only username and password (a test server).
    /// Our own server signs in through the blog only.
    @Published private(set) var offersPasswordLogin = false

    let homeserverURL: String
    private let store: SessionStore
    private var pendingClient: (client: Client, storeID: String)?
    /// Keeps the SDK's auth-error callback registered while signed in.
    private var authErrorHandle: TaskHandle?
    /// The delegate itself: the SDK may hold it weakly.
    private var authErrorDelegate: AuthErrorDelegate?
    private let log = Logger(subsystem: Brand.bundleID, category: "auth")

    init(homeserverURL: String = MatrixClientFactory.homeserverURL(), store: SessionStore = SessionStore()) {
        self.homeserverURL = homeserverURL
        self.store = store
    }

    // MARK: - Start

    func restore() async {
        #if DEBUG
        // UI tests of the signed-out app start without the session a member test left behind.
        if ProcessInfo.processInfo.environment["IPHONEBLOG_SIGNED_OUT"] == "1" {
            store.delete()
            state = .signedOut
            return
        }
        #endif
        guard let stored = store.load() else {
            #if DEBUG
            // Screenshots and UI tests against a test server sign in by themselves.
            let env = ProcessInfo.processInfo.environment
            if let user = env["IPHONEBLOG_DEV_USER"], let password = env["IPHONEBLOG_DEV_PASSWORD"] {
                await signIn(username: user, password: password)
                return
            }
            #endif
            state = .signedOut
            await probeServer()
            return
        }
        do {
            let client = try await MatrixClientFactory.makeClient(homeserverURL: stored.homeserverURL,
                                                                  storeID: stored.storeID,
                                                                  sessionDelegate: KeychainSessionDelegate(store: store, storeID: stored.storeID))
            try await client.restoreSession(session: stored.sdkSession)
            try await begin(client)
        } catch {
            log.error("restore failed: \(error.localizedDescription, privacy: .public)")
            state = .signedOut
            await probeServer()
        }
    }

    /// Asks the server which sign-in it offers. Only a test server offers passwords.
    private func probeServer() async {
        do {
            let client = try await freshClient()
            let details = await client.client.homeserverLoginDetails()
            offersPasswordLogin = details.supportsPasswordLogin() && !details.supportsOauthLogin()
        } catch {
            log.error("server probe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sign in

    /// Step 1 of the blog sign-in: the address to open in the system's web sheet.
    func oauthLoginURL() async throws -> URL {
        let (client, _) = try await freshClient()
        let data = try await client.urlForOauth(oauthConfiguration: Self.oauthConfiguration,
                                                prompt: nil, loginHint: nil, deviceId: nil, additionalScopes: nil)
        guard let url = URL(string: data.loginUrl()) else { throw AuthError.badURL }
        return url
    }

    /// Step 2: the sign-in service sent the browser back to our scheme.
    func completeOAuth(callbackURL: URL) async {
        guard let (client, storeID) = pendingClient else { return }
        state = .signingIn
        do {
            try await client.loginWithOauthCallback(callbackUrl: callbackURL.absoluteString)
            try persist(client, storeID: storeID)
            try await begin(client)
        } catch {
            fail(error)
        }
    }

    func cancelOAuth() {
        state = .signedOut
    }

    /// Username and password, for test servers only.
    func signIn(username: String, password: String) async {
        state = .signingIn
        do {
            let (client, storeID) = try await freshClient()
            try await client.login(username: username, password: password,
                                   initialDeviceName: "\(Brand.appName) iOS", deviceId: nil)
            try persist(client, storeID: storeID)
            try await begin(client)
        } catch {
            fail(error)
        }
    }

    func signOut() async {
        guard case .signedIn(let session) = state else { return }
        authErrorHandle = nil
        await PushCenter.shared.detach()
        await session.stop()
        try? await session.client.logout()
        if let stored = store.load() { MatrixClientFactory.deleteStore(storeID: stored.storeID) }
        store.delete()
        pendingClient = nil
        router.reset()
        state = .signedOut
    }

    /// The server no longer knows this session (revoked in the sign-in service, or the server
    /// was reset): every call answers 401 M_UNKNOWN_TOKEN. Before, the app stayed "signed in"
    /// with #one-Chat locked and nothing working. Now it signs out on this device, without
    /// calling the server, and says why.
    func sessionLost() async {
        guard case .signedIn(let session) = state else { return }
        log.error("session lost: the server refused the token")
        authErrorHandle = nil
        // The screen changes first: stopping sync and removing the pusher talk to a server that
        // no longer accepts the token and may take their time doing so.
        let stored = store.load()
        store.delete()
        pendingClient = nil
        router.reset()
        state = .signedOut
        router.notice = String(localized: "Du wurdest abgemeldet. Bitte melde dich wieder an.")
        await PushCenter.shared.detach()
        await session.stop()
        if let stored { MatrixClientFactory.deleteStore(storeID: stored.storeID) }
    }

    // MARK: - Helpers

    static var oauthConfiguration: OAuthConfiguration {
        OAuthConfiguration(clientName: Brand.appName,
                           redirectUri: Brand.oauthRedirectURI,
                           clientUri: Brand.oauthClientURI,
                           logoUri: Brand.oauthLogoURI,
                           tosUri: Brand.oauthTermsURI,
                           policyUri: Brand.oauthPolicyURI,
                           staticRegistrations: staticRegistrations(clientID: Brand.oauthClientID))
    }

    /// The static MAS client, keyed by homeserver and issuer as the SDK looks them up. WordPress's
    /// web-login accepts only tokens of this client. Empty client id: dynamic registration.
    static func staticRegistrations(clientID: String) -> [String: String] {
        guard !clientID.isEmpty else { return [:] }
        var keys = [Brand.homeserverURL, Brand.oauthIssuerURL]
        keys += keys.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 + "/" }
        return Dictionary(keys.map { ($0, clientID) }, uniquingKeysWith: { first, _ in first })
    }

    /// A client without a session, kept until sign-in finishes.
    private func freshClient() async throws -> (client: Client, storeID: String) {
        if let pendingClient { return pendingClient }
        let storeID = UUID().uuidString
        let client = try await MatrixClientFactory.makeClient(homeserverURL: homeserverURL,
                                                              storeID: storeID,
                                                              sessionDelegate: KeychainSessionDelegate(store: store, storeID: storeID))
        pendingClient = (client, storeID)
        return (client, storeID)
    }

    private func persist(_ client: Client, storeID: String) throws {
        do {
            try store.save(StoredSession(client.session(), storeID: storeID))
        } catch {
            // Without a keychain (an unsigned test build) the app still works until it quits.
            log.error("could not keep the session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func begin(_ client: Client) async throws {
        let session = try ChatSession(client: client, router: router)
        session.onAuthLost = { [weak self] in Task { await self?.sessionLost() } }
        let delegate = AuthErrorDelegate { [weak self] _ in
            Task { @MainActor in await self?.sessionLost() }
        }
        authErrorDelegate = delegate
        authErrorHandle = try? client.setDelegate(delegate: delegate)
        pendingClient = nil
        // Sync first: the screens and the conversation views read its room list service.
        try await session.start()
        state = .signedIn(session)
        router.showSignIn = false
        if !ProcessInfo.processInfo.isRunningTests {
            await PushCenter.shared.attach(session)
        }
    }

    private func fail(_ error: Error) {
        log.error("sign-in failed: \(error.localizedDescription, privacy: .public)")
        errorMessage = String(localized: "Anmeldung fehlgeschlagen. Bitte versuch es noch einmal.")
        state = .signedOut
    }
}

extension ProcessInfo {
    /// Unit and integration tests run inside the app; they must not ask for push permission.
    var isRunningTests: Bool { environment["XCTestConfigurationFilePath"] != nil }
}

enum AuthError: Error {
    case badURL
}

/// The SDK's "unknown token" callback (sync and its own calls). Soft logouts are not used by our
/// server, so both kinds end the session here.
private final class AuthErrorDelegate: ClientDelegate, @unchecked Sendable {
    let onError: (Bool) -> Void
    init(_ onError: @escaping (Bool) -> Void) { self.onError = onError }
    func didReceiveAuthError(isSoftLogout: Bool) { onError(isSoftLogout) }
    func onBackgroundTaskErrorReport(taskName: String, error: BackgroundTaskFailureReason) {}
}
