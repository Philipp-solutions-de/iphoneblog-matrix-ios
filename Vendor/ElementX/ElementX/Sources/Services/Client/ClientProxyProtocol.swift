//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK

enum ClientProxyAction {
    case receivedSyncUpdate
    case receivedAuthError
    case receivedDecryptionError(UnableToDecryptInfo)
    
    var isSyncUpdate: Bool {
        if case .receivedSyncUpdate = self {
            return true
        } else {
            return false
        }
    }
}

enum ClientProxyLoadingState {
    case loading
    case notLoading
}

enum ClientProxyPresence: Equatable, Sendable {
    case online
    case unavailable
    case offline
}

enum ClientProxyError: Error {
    case sdkError(Error)
    case forbiddenAccess
    
    case invalidMedia
    case invalidServerName
    case invalidHomeserverURL
    case failedUploadingMedia(ErrorKind)
    case roomPreviewIsPrivate
    case failedRetrievingUserIdentity
    case failedResolvingRoomAlias
    case roomNotInLocalStore
    case invalidInvite
}

enum SlidingSyncConstants {
    static let maximumVisibleRangeSize = 30
}

enum CreateRoomAccessType: Equatable {
    case `public`
    case spaceMembers(spaceID: String)
    case askToJoinWithSpaceMembers(spaceID: String)
    case askToJoin
    case `private`
    
    var isVisibilityPrivate: Bool {
        switch self {
        case .private, .spaceMembers, .askToJoinWithSpaceMembers:
            true
        case .public, .askToJoin:
            false
        }
    }
}

/// This struct represents the configuration that we are using to register the application through Pusher to Sygnal
/// using the Matrix Rust SDK, more info here:
/// https://github.com/matrix-org/sygnal
struct PusherConfiguration: Equatable {
    let identifiers: PusherIdentifiers
    let kind: PusherKind
    let appDisplayName: String
    let deviceDisplayName: String
    let profileTag: String?
    let lang: String
    /// Whether to keep the pushers of the other accounts using the same pushkey on this device.
    let append: Bool
}

enum SessionVerificationState {
    case unknown
    case verified
    case unverified
}

/// The `Decodable` conformance is just for the purpose of migration
enum TimelineMediaVisibility: Decodable {
    case always
    case privateOnly
    case never
}

/// Represents a server-echoed update about the current user's own beacon info state in a room.
struct LiveLocationOwnInfoUpdate: Equatable {
    /// The room where the beacon info event was sent.
    let roomID: String
    /// The event ID of the beacon info state event.
    let eventID: String
    /// Whether the beacon is currently active (live) or has been stopped.
    let isLive: Bool
}

// iphoneblog: only the members the vendored chat views use. Shim/ChatClientProxy.swift
// implements it on the SDK client; the rest of Element X's client proxy is not vendored.
protocol ClientProxyProtocol: AnyObject {
    var homeserverReachabilityPublisher: CurrentValuePublisher<HomeserverReachability, Never> { get }
    
    var userID: String { get }
    
    var homeserver: String { get }
    
    var userIDServerName: String? { get }
    
    var timelineMediaVisibilityPublisher: CurrentValuePublisher<TimelineMediaVisibility, Never> { get }
    
    var mediaLoader: MediaLoaderProtocol { get }
    
    func roomSummaryForIdentifier(_ identifier: String) -> RoomSummary?
    
    func roomSummaryForAlias(_ alias: String) -> RoomSummary?
    
    func resolveRoomAlias(_ alias: String) async -> Result<ResolvedRoomAlias, ClientProxyError>
    
    func userIdentity(for userID: String, fallBackToServer: Bool) async -> Result<UserIdentityProxyProtocol?, ClientProxyError>
}
