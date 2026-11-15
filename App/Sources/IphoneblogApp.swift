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
    @StateObject private var guestFeed = GuestBlogFeed()

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView()
        case .signedOut, .signingIn:
            MainView(router: model.router, guestFeed: guestFeed, session: nil)
        case .signedIn(let session):
            MainView(router: model.router, guestFeed: guestFeed, session: session)
        }
    }
}
