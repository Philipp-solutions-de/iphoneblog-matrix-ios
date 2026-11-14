//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Stand-ins for app-level types Element X's views reach for: the app mediator (open a link,
// open Settings, camera check) and the forwarding payload of a feature we left out.

import AVFoundation
import MatrixRustSDK
import UIKit

/// What the vendored views ask of the app. Element X's version also carries its window manager
/// and network monitor, which these views do not use.
protocol AppMediatorProtocol {
    var appState: UIApplication.State { get }
    /// Changes at runtime (e.g. while the camera is in use), so check it before each use.
    var isCameraAvailable: Bool { get }
    func open(_ url: URL)
    func openAppSettings()
    func setIdleTimerDisabled(_ disabled: Bool)
    func requestAuthorizationIfNeeded() async -> Bool
}

struct AppMediator: AppMediatorProtocol {
    /// Where links from messages go. The app routes them (blog articles open in place).
    var openURL: (URL) -> Void

    var appState: UIApplication.State { UIApplication.shared.applicationState }
    var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    func open(_ url: URL) { openURL(url) }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// Forwarding is left out of our app; the type stays so the timeline's menu code compiles.
struct MessageForwardingPayload: Hashable {
    let ids: [TimelineItemIdentifier]
    let roomID: String
    let contents: [RoomMessageEventContentWithoutRelation]

    static func == (lhs: MessageForwardingPayload, rhs: MessageForwardingPayload) -> Bool {
        lhs.ids == rhs.ids && lhs.roomID == rhs.roomID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ids)
        hasher.combine(roomID)
    }
}
