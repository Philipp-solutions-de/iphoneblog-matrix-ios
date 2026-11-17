//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// The services Element X's chat views expect, built on the app's SDK client. Element X's own
// client proxy and user session carry sync, spaces, calls, encryption and notifications; ours
// carry only what the views read (Services/Client/ClientProxyProtocol.swift lists it).

import Combine
import Foundation
import MatrixRustSDK
import UIKit

/// Element X's client proxy, cut to what the timeline, composer and media views use.
final class ChatClientProxy: ClientProxyProtocol {
    let client: Client
    let userID: String
    let mediaLoader: MediaLoaderProtocol

    private let reachabilitySubject = CurrentValueSubject<HomeserverReachability, Never>(.reachable)
    private let mediaVisibilitySubject = CurrentValueSubject<TimelineMediaVisibility, Never>(.always)

    init(client: Client) throws {
        self.client = client
        userID = try client.userId()
        mediaLoader = MediaLoader(client: client)
    }

    var homeserverReachabilityPublisher: CurrentValuePublisher<HomeserverReachability, Never> {
        reachabilitySubject.asCurrentValuePublisher()
    }

    /// Images load in the timeline right away. Our rooms are a members' community, not strangers.
    var timelineMediaVisibilityPublisher: CurrentValuePublisher<TimelineMediaVisibility, Never> {
        mediaVisibilitySubject.asCurrentValuePublisher()
    }

    var homeserver: String { client.homeserver() }

    var userIDServerName: String? { try? client.userIdServerName() }

    var maxMediaUploadSize: Result<UInt, ClientProxyError> {
        get async {
            do {
                return try await .success(UInt(client.getMaxMediaUploadSize()))
            } catch {
                MXLog.error("Failed checking the max media upload size with error: \(error)")
                return .failure(.sdkError(error))
            }
        }
    }

    /// Element X looks rooms up in its room list for pills that name a room. Our app keeps the
    /// list itself, so a room pill shows its alias or ID instead of the room's name.
    func roomSummaryForIdentifier(_ identifier: String) -> RoomSummary? { nil }

    func roomSummaryForAlias(_ alias: String) -> RoomSummary? { nil }

    func resolveRoomAlias(_ alias: String) async -> Result<ResolvedRoomAlias, ClientProxyError> {
        do {
            guard let resolved = try await client.resolveRoomAlias(roomAlias: alias) else {
                return .failure(.failedResolvingRoomAlias)
            }
            return .success(ResolvedRoomAlias(roomId: resolved.roomId, servers: Array(resolved.servers.prefix(50))))
        } catch {
            MXLog.error("Failed resolving room alias: \(alias) with error: \(error)")
            return .failure(.sdkError(error))
        }
    }

    /// Our rooms are unencrypted, so there are no identities to check.
    func userIdentity(for userID: String, fallBackToServer: Bool) async -> Result<UserIdentityProxyProtocol?, ClientProxyError> {
        .success(nil)
    }
}

/// Element X's user session, cut to what the chat views use.
final class ChatUserSession: UserSessionProtocol, @unchecked Sendable {
    let clientProxy: ClientProxyProtocol
    let userSettings: UserSettings
    let mediaProvider: MediaProviderProtocol
    let voiceMessageMediaManager: VoiceMessageMediaManagerProtocol
    let liveLocationService: LiveLocationServiceProtocol = NoLiveLocationService()
    let contentScannerService: ContentScannerServiceProtocol? = nil
    let callbacks = PassthroughSubject<UserSessionCallback, Never>()

    /// No encryption, so every device counts as verified and no recovery is set up.
    let sessionSecurityStatePublisher = CurrentValueSubject<SessionSecurityState, Never>(
        SessionSecurityState(verificationState: .verified, recoveryState: .disabled)
    ).asCurrentValuePublisher()

    init(clientProxy: ChatClientProxy, userSettings: UserSettings) {
        self.clientProxy = clientProxy
        self.userSettings = userSettings
        let mediaProvider = MediaProvider(mediaLoader: clientProxy.mediaLoader,
                                          imageCache: .onlyInMemory,
                                          homeserverReachabilityPublisher: clientProxy.homeserverReachabilityPublisher)
        // Images decoded and scaled off the main thread (PreparedMediaProvider.swift).
        self.mediaProvider = PreparedMediaProvider(base: mediaProvider)
        voiceMessageMediaManager = VoiceMessageMediaManager(mediaProvider: mediaProvider)
    }
}

/// The orientation calls of Element X's camera picker. Our app turns with the device.
struct ChatOrientationManager: OrientationManagerProtocol {
    func setOrientation(_ orientation: UIInterfaceOrientationMask) { }
    func lockOrientation(_ orientation: UIInterfaceOrientationMask) { }
}
