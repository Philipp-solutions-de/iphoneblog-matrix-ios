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
                .task { await model.restore() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView()
        case .signedOut, .signingIn:
            SignInView()
        case .signedIn(let session):
            MainView(session: session, router: session.router, rooms: session.rooms)
        }
    }
}
