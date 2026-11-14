import OSLog
import UIKit
import UserNotifications

/// Connects iOS push to the signed-in session: asks for permission, hands the APNs token to
/// Sygnal through `ChatSession.registerPusher`, and opens the room when a push is tapped.
@MainActor
final class PushCenter: NSObject, ObservableObject {
    static let shared = PushCenter()

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private var token: Data?
    private weak var session: ChatSession?
    /// A push tapped while the app was still starting; opened once the session is there.
    private var pendingTap: [AnyHashable: Any]?
    private let log = Logger(subsystem: Brand.bundleID, category: "push")

    /// Called once the account is signed in: ask for permission, then register for pushes.
    func attach(_ session: ChatSession) async {
        self.session = session
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorization()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        if let token { await session.registerPusher(token: token) }
        if let pendingTap {
            self.pendingTap = nil
            open(userInfo: pendingTap)
        }
    }

    func detach() async {
        await session?.unregisterPusher()
        session = nil
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    fileprivate func didRegister(token: Data) {
        self.token = token
        guard let session else { return }
        Task { await session.registerPusher(token: token) }
    }

    fileprivate func didFailToRegister(_ error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    fileprivate func open(userInfo: [AnyHashable: Any]) {
        guard let roomID = userInfo["room_id"] as? String else { return }
        guard session != nil else {
            pendingTap = userInfo
            return
        }
        if let threadRoot = userInfo["thread_root"] as? String {
            session?.openThread(roomID: roomID, rootEventID: threadRoot)
        } else {
            session?.openRoom(roomID: roomID)
        }
    }
}

extension PushCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // In the foreground the room list shows the message; a banner would only repeat it.
        [.badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { PushCenter.shared.open(userInfo: userInfo) }
    }
}

/// The UIKit side of push: iOS delivers the device token to the app delegate.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch ends, so a tap that started the app reaches us.
        UNUserNotificationCenter.current().delegate = PushCenter.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushCenter.shared.didRegister(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushCenter.shared.didFailToRegister(error)
    }
}
