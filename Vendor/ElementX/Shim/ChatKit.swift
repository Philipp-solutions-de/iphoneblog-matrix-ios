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

/// The app's look for ChatKit: our own views read `ChatKitStyle.current`, Element X's views read
/// Compound's design tokens, which are recoloured here. Call once at app start.
public enum ChatKitTheme {
    @MainActor
    public static func apply(_ style: ChatKitStyle) {
        registerMentionPills()
        ChatKitStyle.current = style
        let c = style.colors
        let colors = Color.compound
        // Text and canvas.
        colors.override(\.textPrimary, with: c.ink)
        colors.override(\.textSecondary, with: c.ink2)
        colors.override(\.bgCanvasDefault, with: c.background)
        // Links, buttons and accents: teal.
        colors.override(\.textActionAccent, with: c.accent)
        colors.override(\.textLinkExternal, with: c.accent)
        colors.override(\.iconAccentPrimary, with: c.accentBright)
        colors.override(\.iconAccentTertiary, with: c.accentBright)
        colors.override(\.bgAccentRest, with: c.accent)
        colors.override(\.bgAccentHovered, with: c.accent)
        colors.override(\.bgAccentPressed, with: c.accent)
        colors.override(\.bgActionPrimaryRest, with: c.accent)
        // Reactions: yours on soft teal with a teal edge, others' on the raised surface.
        colors.override(\.bgSubtlePrimary, with: c.accentSoft)
        colors.override(\.borderInteractivePrimary, with: c.accent)
        colors.override(\.bgSubtleSecondary, with: c.surface)
        // Mentions of you: white on solid teal. Others' mentions: Shim/LeftOut.swift, MentionPillColors.
        colors.override(\.bgBadgeAccent, with: c.highlightSoft)
        colors.override(\.textBadgeAccent, with: c.highlight)
        // Raised canvas (sheets, menus) and dividers, so dark mode sits on the blog's #111.
        colors.override(\.bgCanvasDefaultLevel1, with: c.surface)
        colors.override(\.bgSubtleSecondaryLevel0, with: c.surface)
        colors.override(\.borderInteractiveSecondary, with: c.line)
        // UIKit parts (the timeline's table view, its separators) read Compound's UIColor tokens.
        // A UIColor made from these Colors keeps their light and dark variants.
        let ui = UIColor.compound
        ui.override(\.bgCanvasDefault, with: UIColor(c.background))
        ui.override(\.textPrimary, with: UIColor(c.ink))
        ui.override(\.textSecondary, with: UIColor(c.ink2))
        ui.override(\.iconTertiary, with: UIColor(c.ink3))
        ui.override(\.borderInteractiveSecondary, with: UIColor(c.line))
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
        ChatPostingNotice.shared.client = client
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

    /// Every thread you take part in, across all rooms, newest first. The app gives it its title.
    public func threadsView(host: ChatKitHost) -> AnyView {
        AnyView(ChatThreadsListView(model: self.threadsModel,
                                    mediaProvider: userSession.mediaProvider) { [weak host] entry in
            host?.openThread(roomID: entry.roomID, rootEventID: entry.rootEventID)
        })
    }

    /// Shows a message in its room's timeline, in context (a search result's tap).
    public func focus(roomID: String, eventID: String) {
        ChatFocusRequests.shared.pending = .init(roomID: roomID, eventID: eventID)
    }

    /// The "Threads" row for the top of a channel: your threads with news, counted.
    public func threadsEntryView(open: @escaping () -> Void) -> AnyView {
        AnyView(ChatThreadsEntryRow(model: self.threadsModel, open: open))
    }

    private lazy var threadsModel = ChatThreadsListModel(client: self.clientProxy.client, ownUserID: self.clientProxy.userID)

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
