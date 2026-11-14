//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// ChatKit's public face: the only types the app uses. Everything else in this framework is
// Element X's code (Vendor/ElementX) or a small replacement for a part we left out (Shim/).
// The app talks to it through App/Sources/Bridge (docs/architecture.md, "Kept apart").

import Combine
import Compound
import MatrixRustSDK
import SwiftUI

/// What ChatKit asks of the app: navigation and links. The app owns the navigation, so a thread
/// opens wherever the app puts threads (a pushed screen on iPhone, a column on iPad).
@MainActor
public protocol ChatKitHost: AnyObject {
    /// The reader tapped "n replies" under a message, or chose "Reply in thread".
    func openThread(roomID: String, rootEventID: String)
    /// A link or pill that names another room.
    func openRoom(roomID: String)
    /// The reader tapped a sender's name or avatar.
    func openUser(userID: String)
    /// A web link in a message. The app decides where it opens.
    func openURL(_ url: URL)
    /// A short notice for something ChatKit does not offer.
    func showMessage(_ text: String)
}

/// The blog's colours for Element X's design tokens. Call once at app start.
public enum ChatKitTheme {
    /// - Parameters:
    ///   - accent: the blog's teal, for accents and icons.
    ///   - accentText: the darker teal, where white text sits on it or teal text sits on white.
    ///   - highlight: coral, for what is meant for the reader (mentions, badges).
    @MainActor
    public static func apply(accent: Color, accentText: Color, highlight: Color) {
        registerMentionPills()
        let colors = Color.compound
        colors.override(\.textActionAccent, with: accentText)
        colors.override(\.textLinkExternal, with: accentText)
        colors.override(\.iconAccentPrimary, with: accent)
        colors.override(\.iconAccentTertiary, with: accent)
        colors.override(\.bgAccentRest, with: accent)
        colors.override(\.bgAccentHovered, with: accentText)
        colors.override(\.bgAccentPressed, with: accentText)
        colors.override(\.bgActionPrimaryRest, with: accentText)
        colors.override(\.bgBadgeAccent, with: highlight)
    }

    /// Element X's app delegate registers the view that draws a mention as a name pill.
    private static var pillsRegistered = false
    @MainActor
    private static func registerMentionPills() {
        guard !pillsRegistered else { return }
        NSTextAttachment.registerViewProviderClass(PillAttachmentViewProvider.self, forFileType: InfoPlistReader.main.pillsUTType)
        pillsRegistered = true
    }
}

/// One signed-in account's chat screens. The app creates it after sign-in, beside its own room
/// list, and keeps it for the session.
@MainActor
public final class ChatKitSession {
    let userSession: ChatUserSession
    let clientProxy: ChatClientProxy
    let roomListService: RoomListService
    let analytics: AnalyticsServiceProtocol = NoAnalytics()
    let emojiProvider: EmojiProviderProtocol
    let linkMetadataProvider: LinkMetadataProviderProtocol = LinkMetadataProvider()
    let timelineControllerFactory: TimelineControllerFactoryProtocol
    let mediaPlayerProvider: MediaPlayerProviderProtocol = MediaPlayerProvider()

    private var roomProxies: [String: JoinedRoomProxyProtocol] = [:]

    /// - Parameters:
    ///   - client: the signed-in SDK client.
    ///   - roomListService: the room list service of the app's running sync service.
    public init(client: Client, roomListService: RoomListService) throws {
        let settings = UserSettings()
        clientProxy = try ChatClientProxy(client: client)
        userSession = ChatUserSession(clientProxy: clientProxy, userSettings: settings)
        self.roomListService = roomListService
        emojiProvider = EmojiProvider(userSettings: settings)
        timelineControllerFactory = TimelineControllerFactory(userSettings: settings)
    }

    /// A channel or direct message: its timeline with threads, reactions, replies and the composer.
    public func roomView(roomID: String, host: ChatKitHost) -> AnyView {
        AnyView(ChatScreenLoader(id: roomID) { [weak self, weak host] presenter in
            guard let self, let host else { throw ChatKitError.sessionEnded }
            let roomProxy = try await joinedRoomProxy(roomID)
            return ChatRoomCoordinator(session: self, roomProxy: roomProxy, presenter: presenter, host: host)
        })
    }

    /// One thread: the first message on top, its replies below, a composer that answers in it.
    public func threadView(roomID: String, rootEventID: String, host: ChatKitHost) -> AnyView {
        AnyView(ChatScreenLoader(id: "\(roomID)/\(rootEventID)") { [weak self, weak host] presenter in
            guard let self, let host else { throw ChatKitError.sessionEnded }
            let roomProxy = try await joinedRoomProxy(roomID)
            return try await ChatThreadCoordinator(session: self, roomProxy: roomProxy, rootEventID: rootEventID,
                                                   presenter: presenter, host: host)
        })
    }

    func joinedRoomProxy(_ roomID: String) async throws -> JoinedRoomProxyProtocol {
        if let proxy = roomProxies[roomID] { return proxy }
        let room = try roomListService.room(roomId: roomID)
        let proxy = try await JoinedRoomProxy(roomListService: roomListService,
                                              room: room,
                                              userSettings: userSession.userSettings,
                                              analyticsService: analytics,
                                              eventStringBuilder: .pinnedEventStringBuilder(userID: clientProxy.userID))
        // As Element X's room flow does before it shows a room: live updates for this room.
        await proxy.subscribeForUpdates()
        roomProxies[roomID] = proxy
        return proxy
    }

    func timelineItemFactory() -> RoomTimelineItemFactory {
        RoomTimelineItemFactory(userID: clientProxy.userID,
                                attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                stateEventStringBuilder: RoomStateEventStringBuilder(userID: clientProxy.userID))
    }

    func appMediator(host: ChatKitHost) -> AppMediatorProtocol {
        AppMediator { [weak host] url in host?.openURL(url) }
    }
}

enum ChatKitError: Error {
    case sessionEnded
    case threadUnavailable
}
