//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// The one file of Vendor/ElementX that the app target compiles: it implements the app's
// ChatScreenProviding (App/Sources/Bridge/ChatScreens.swift) with ChatKit's screens. Swapping the
// conversation views for another kit means replacing this file and the ChatKit framework.

import ChatKit
import MatrixRustSDK
import SwiftUI

@MainActor
final class ElementXChatScreens: ChatScreenProviding {
    private var session: ChatKitSession?
    private var sessionUserID: String?
    private var hosts: [ObjectIdentifier: HostAdapter] = [:]

    init() {
        ChatKitTheme.apply(.app)
        ChatKitText.preview = { body, html in PushText.plain(body: body, formattedBody: html) }
        // "Link kopieren": the app's readable link (ChatLink), not matrix.to.
        ChatKitLinks.message = { roomID, alias, eventID in ChatLink.url(roomID: roomID, alias: alias, eventID: eventID) }
    }

    func start(host: ChatHost) async throws {
        guard sessionUserID != host.userID || session == nil else { return }
        ChatPostingNotice.shared.privacyURL = URL(string: Brand.oauthPolicyURI)
        session = try ChatKitSession(client: host.client, roomListService: host.roomListService)
        sessionUserID = host.userID
        hosts = [:]
        ChatKitContacts.share = { [weak host] userID in host?.shareContact(userID: userID) }
        ChatKitReads.seen = { [weak host] roomID, threadRoot, eventID in
            host?.didSee(roomID: roomID, threadRootEventID: threadRoot, eventID: eventID)
        }
    }

    func roomScreen(roomID: String, host: ChatHost) -> AnyView {
        guard let session else { return AnyView(ProgressView()) }
        return session.roomView(roomID: roomID, host: adapter(for: host))
    }

    func threadScreen(roomID: String, rootEventID: String, host: ChatHost) -> AnyView {
        guard let session else { return AnyView(ProgressView()) }
        return session.threadView(roomID: roomID, rootEventID: rootEventID, host: adapter(for: host))
    }

    func discussionScreen(roomID: String, rootEventID: String, host: ChatHost) -> AnyView {
        AnyView(threadScreen(roomID: roomID, rootEventID: rootEventID, host: host)
            .environment(\.chatThreadHeaderHidden, true))
    }

    func focus(roomID: String, eventID: String) {
        session?.focus(roomID: roomID, eventID: eventID)
    }

    func threadsEntry(host: ChatHost, open: @escaping () -> Void) -> AnyView {
        guard let session else { return AnyView(EmptyView()) }
        return session.threadsEntryView(open: open)
    }

    func threadsScreen(host: ChatHost) -> AnyView {
        guard let session else { return AnyView(ProgressView()) }
        return session.threadsView(host: adapter(for: host))
    }

    /// ChatKit holds its host weakly; the adapter lives here for as long as the account does.
    private func adapter(for host: ChatHost) -> HostAdapter {
        let key = ObjectIdentifier(host)
        if let adapter = hosts[key] { return adapter }
        let adapter = HostAdapter(host)
        hosts[key] = adapter
        return adapter
    }
}

/// Hands ChatKit's navigation requests to the app's ChatHost.
@MainActor
private final class HostAdapter: ChatKitHost {
    private weak var host: ChatHost?

    init(_ host: ChatHost) { self.host = host }

    func openThread(roomID: String, rootEventID: String) { host?.openThread(roomID: roomID, rootEventID: rootEventID) }
    func openRoom(roomID: String) { host?.openRoom(roomID: roomID) }
    func openUser(userID: String) { host?.openUser(userID: userID) }
    func openURL(_ url: URL) { host?.openURL(url) }
    func showMessage(_ text: String) { host?.showMessage(text) }
}
