import SwiftUI

@main
struct IphoneblogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.teal)
                .preferredColorScheme(Self.forcedScheme)
                .task { await model.restore() }
                // Chat links on chat.iphoneblog.de (universal links) open the message in the app.
                .onOpenURL { model.open($0) }
                // The frame-rate readout and the device metrics (docs/performance.md).
                .background(PerfInstrumentsHook().frame(width: 0, height: 0))
                .onAppear { MetricsReporter.shared.start() }
        }
    }
}

extension IphoneblogApp {
    /// Screenshot runs in dark or light without touching the simulator's setting
    /// (IPHONEBLOG_APPEARANCE=dark|light, debug builds); otherwise the system's.
    static var forcedScheme: ColorScheme? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["IPHONEBLOG_APPEARANCE"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView()
        case .signedOut, .signingIn:
            MainView(router: model.router, session: nil)
        case .signedIn(let session):
            SignedInMain(router: model.router, session: session)
        }
    }
}

/// Watches the session and its lists so the tab badges follow them.
private struct SignedInMain: View {
    @ObservedObject var router: Router
    @ObservedObject var session: ChatSession
    @ObservedObject var rooms: RoomListModel
    @ObservedObject var mentions: MentionsModel

    init(router: Router, session: ChatSession) {
        self.router = router
        self.session = session
        rooms = session.rooms
        mentions = session.mentions
    }

    var body: some View { MainView(router: router, session: session) }
}
