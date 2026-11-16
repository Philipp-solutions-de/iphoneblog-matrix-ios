//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// The conversation screens' values, beside the rest of the theme. They belong in
// App/Sources/Theme.swift and live here only until the app session moves them there; nothing
// else changes when they move.

import ChatKit
import SwiftUI

extension Theme {
    enum Chat {
        /// Sender name and the time beside it.
        static let senderName = SwiftUI.Font.system(size: 15, weight: .bold)
        static let time = SwiftUI.Font.system(size: 12)
        /// "5 Antworten" and the last reply after it.
        static let threadSummary = SwiftUI.Font.system(size: 14, weight: .bold)
        static let threadPreview = SwiftUI.Font.system(size: 13)
        /// "# allgemein" and "148 Mitglieder" in the navigation bar.
        static let roomTitle = SwiftUI.Font.system(size: 17, weight: .bold)
        static let roomSubtitle = SwiftUI.Font.system(size: 13)
        /// "Heute" and "5 Antworten" above a thread's replies.
        static let divider = SwiftUI.Font.system(size: 13, weight: .semibold)

        /// The sender's avatar, the small one in a thread summary.
        static let avatar: CGFloat = 36
        static let summaryAvatar: CGFloat = 20
        /// Gap between avatar and message; space above a new sender, between one sender's messages.
        static let avatarGap: CGFloat = 12
        static let groupSpacing: CGFloat = 14
        static let messageSpacing: CGFloat = 4
        /// Widest a picture or video in the timeline may be.
        static let mediaWidth: CGFloat = 280
    }
}

extension ChatKitStyle {
    /// The app's theme, as ChatKit takes it.
    static var app: ChatKitStyle {
        ChatKitStyle(
            colors: .init(accent: Theme.teal, accentBright: Theme.tealBright, accentSoft: Theme.tealSoft,
                          highlight: .white, highlightSoft: Theme.badge,
                          ink: Theme.ink, ink2: Theme.ink2, ink3: Theme.ink3,
                          background: Theme.background, surface: Theme.surface, line: Theme.line,
                          avatars: Theme.avatarColors),
            fonts: .init(senderName: Theme.Chat.senderName, time: Theme.Chat.time,
                         threadSummary: Theme.Chat.threadSummary, threadPreview: Theme.Chat.threadPreview,
                         roomTitle: Theme.Chat.roomTitle, roomSubtitle: Theme.Chat.roomSubtitle,
                         dayDivider: Theme.Chat.divider),
            metrics: .init(page: Theme.Space.page - 4, avatarGap: Theme.Chat.avatarGap, avatar: Theme.Chat.avatar,
                           summaryAvatar: Theme.Chat.summaryAvatar, groupSpacing: Theme.Chat.groupSpacing,
                           messageSpacing: Theme.Chat.messageSpacing,
                           mediaWidth: Theme.Chat.mediaWidth, corner: Theme.Size.corner)
        )
    }
}
