import SwiftUI

/// Channels first, then direct messages. The skeleton lists them; the timeline comes next.
struct RoomListView: View {
    @EnvironmentObject private var model: AppModel
    let session: ChatSession
    @ObservedObject var rooms: RoomListModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("Kanäle") {
                    ForEach(rooms.channels) { room in
                        Label(room.name, systemImage: "number")
                            .accessibilityIdentifier("room.\(room.name)")
                    }
                }
                if !rooms.directMessages.isEmpty {
                    Section("Direktnachrichten") {
                        ForEach(rooms.directMessages) { room in
                            Label(room.name, systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            .overlay {
                if !rooms.hasLoaded { ProgressView() }
            }
            .navigationTitle(Brand.appName)
            .toolbar {
                Menu {
                    Text(session.userID)
                    Button("Abmelden", role: .destructive) {
                        Task { await model.signOut() }
                    }
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        } detail: {
            Text("Wähl einen Kanal.")
                .foregroundStyle(.secondary)
        }
    }
}
