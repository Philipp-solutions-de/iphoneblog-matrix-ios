import SwiftUI

@main
struct IphoneblogApp: App {
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
            RoomListView(session: session, rooms: session.rooms)
        }
    }
}
