import Foundation
import MatrixRustSDK
import OSLog

/// A signed-in account: the client, its sync loop and the room list.
@MainActor
final class ChatSession: ObservableObject {
    let client: Client
    let userID: String
    let rooms = RoomListModel()

    @Published private(set) var syncState: SyncServiceState = .idle

    private var syncService: SyncService?
    private var stateHandle: TaskHandle?
    private let log = Logger(subsystem: Brand.bundleID, category: "sync")

    init(client: Client) throws {
        self.client = client
        userID = try client.userId()
    }

    /// Starts sliding sync and the room list. Safe to call again after `stop()`.
    func start() async throws {
        if syncService == nil {
            let service = try await client.syncService().finish()
            syncService = service
            stateHandle = service.state(listener: SyncStateObserver { [weak self] state in
                Task { @MainActor in self?.syncState = state }
            })
            try await rooms.attach(to: service.roomListService())
        }
        await syncService?.start()
        log.info("sync started for \(self.userID, privacy: .private)")
    }

    func stop() async {
        await syncService?.stop()
    }
}

private final class SyncStateObserver: SyncServiceStateObserver, @unchecked Sendable {
    let onChange: (SyncServiceState) -> Void
    init(_ onChange: @escaping (SyncServiceState) -> Void) { self.onChange = onChange }
    func onUpdate(state: SyncServiceState) { onChange(state) }
}
