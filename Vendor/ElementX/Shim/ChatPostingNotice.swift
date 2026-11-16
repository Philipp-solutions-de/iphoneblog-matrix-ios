//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Before someone's very first post, once: who will see it (Thorsten's privacy decision,
// 2026-11-16). The acknowledgement lives in the account's data (de.iphoneblog.posting_notice),
// so other devices and the web app, which uses the same key, do not ask again. Every send in
// TimelineProxy (patch) waits for `ensureAcknowledged()`; "Abbrechen" sends nothing.

import MatrixRustSDK
import OSLog
import SwiftUI
import UIKit

@MainActor
public final class ChatPostingNotice {
    public static let shared = ChatPostingNotice()

    static let eventType = "de.iphoneblog.posting_notice"
    /// The app's privacy page, set by the app (Brand.oauthPolicyURI).
    public var privacyURL: URL?
    var client: Client?
    private var acknowledged = false
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    private let log = Logger(subsystem: "de.iphoneblog.chatkit", category: "posting-notice")

    /// True once the person has read the notice, now or on any device before; false if they
    /// cancelled. Shows the notice at most once at a time.
    func ensureAcknowledged() async -> Bool {
        if acknowledged { return true }
        if await hasAcknowledged() {
            acknowledged = true
            return true
        }
        log.info("posting notice: not yet acknowledged, asking")
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { present() }
        }
    }

    /// The account data, looked up for at most 3 s (the SDK may wait for a sync); a slow answer
    /// counts as not yet acknowledged, and the notice shows.
    private func hasAcknowledged() async -> Bool {
        guard let client else { return false }
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { (try? await client.accountData(eventType: Self.eventType)).flatMap { $0 } != nil }
            group.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
    }

    private func present() {
        let view = PostingNoticeView(privacyURL: privacyURL) { [weak self] ok in self?.answer(ok) }
        let controller = UIHostingController(rootView: view)
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium()]
        controller.isModalInPresentation = true
        guard let top = Self.topViewController() else {
            log.error("posting notice: no screen to show it on")
            answer(true)
            return
        }
        log.info("posting notice: shown over \(String(describing: type(of: top)), privacy: .public)")
        top.present(controller, animated: true)
    }

    private func answer(_ ok: Bool) {
        Self.topViewController()?.dismiss(animated: true)
        if ok {
            acknowledged = true
            if let client {
                Task { try? await client.setAccountData(eventType: Self.eventType, content: #"{"acknowledged":true}"#) }
            }
        }
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(returning: ok) }
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

struct PostingNoticeView: View {
    let privacyURL: URL?
    let answer: (Bool) -> Void
    @Environment(\.openURL) private var openURL

    private var style: ChatKitStyle { ChatKitStyle.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bevor du schreibst")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(style.colors.ink)
            Text("Deine Beiträge sind für #one-Mitglieder sichtbar, Beiträge in Artikel-Diskussionen auch öffentlich auf iphoneblog.de.")
                .font(.system(size: 17))
                .foregroundStyle(style.colors.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let privacyURL {
                Button("Details in der Datenschutzerklärung") { openURL(privacyURL) }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(style.colors.accent)
            }
            Spacer(minLength: 8)
            Button { answer(true) } label: {
                Text("Verstanden").font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(style.colors.accent)
            .accessibilityIdentifier("posting-notice.ok")
            Button("Abbrechen") { answer(false) }
                .frame(maxWidth: .infinity)
                .foregroundStyle(style.colors.ink3)
        }
        .padding(24)
    }
}
