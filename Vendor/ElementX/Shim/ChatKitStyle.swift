//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Every visual value ChatKit's own views use, handed in by the app from its one theme file
// (App/Sources/Theme.swift, mapped in Vendor/ElementX/Adapter). Design feedback changes the
// theme file; nothing in ChatKit names a colour, a font size or a margin itself.

import SwiftUI

public struct ChatKitStyle {
    public struct Colors {
        /// Links, buttons, "5 Antworten": the dark teal white text can sit on.
        public var accent: Color
        /// The blog's own teal, for small accents.
        public var accentBright: Color
        /// Soft teal behind your own reactions and others' mentions.
        public var accentSoft: Color
        /// A mention of you: its text.
        public var highlight: Color
        /// A mention of you: its fill.
        public var highlightSoft: Color
        /// Text: main, secondary, faint.
        public var ink: Color
        public var ink2: Color
        public var ink3: Color
        /// Page, raised surfaces, hairlines.
        public var background: Color
        public var surface: Color
        public var line: Color
        /// Initials avatars, one colour per person.
        public var avatars: [Color]
        /// The bot marks, the "Bot" pill and a bot's name: teal everywhere, inside #one too, where
        /// the accent turns red (Thorsten, 2026-11-20).
        public var bot: Color

        public init(accent: Color, accentBright: Color, accentSoft: Color, highlight: Color, highlightSoft: Color,
                    ink: Color, ink2: Color, ink3: Color, background: Color, surface: Color, line: Color, avatars: [Color],
                    bot: Color? = nil) {
            self.bot = bot ?? accent
            self.accent = accent
            self.accentBright = accentBright
            self.accentSoft = accentSoft
            self.highlight = highlight
            self.highlightSoft = highlightSoft
            self.ink = ink
            self.ink2 = ink2
            self.ink3 = ink3
            self.background = background
            self.surface = surface
            self.line = line
            self.avatars = avatars
        }
    }

    public struct Fonts {
        /// Sender name above a group of messages.
        public var senderName: Font
        /// Time beside the sender name.
        public var time: Font
        /// "5 Antworten" under a message, and the replies count in a thread.
        public var threadSummary: Font
        /// The last reply's sender and text beside it.
        public var threadPreview: Font
        /// Room title and subtitle in the navigation bar.
        public var roomTitle: Font
        public var roomSubtitle: Font
        /// "Heute" between days.
        public var dayDivider: Font

        public init(senderName: Font, time: Font, threadSummary: Font, threadPreview: Font,
                    roomTitle: Font, roomSubtitle: Font, dayDivider: Font) {
            self.senderName = senderName
            self.time = time
            self.threadSummary = threadSummary
            self.threadPreview = threadPreview
            self.roomTitle = roomTitle
            self.roomSubtitle = roomSubtitle
            self.dayDivider = dayDivider
        }
    }

    public struct Metrics {
        /// Left and right margin of a message row.
        public var page: CGFloat
        /// Gap between avatar and message.
        public var avatarGap: CGFloat
        /// The sender's avatar beside the first message of a group.
        public var avatar: CGFloat
        /// The small avatar in a thread summary.
        public var summaryAvatar: CGFloat
        /// Space above a new sender's group, and between messages of one group.
        public var groupSpacing: CGFloat
        public var messageSpacing: CGFloat
        /// Widest a picture or video may be, and the rounding of its corners.
        public var mediaWidth: CGFloat
        public var corner: CGFloat
        /// A person's picture is a squircle: its corner radius is this share of its side.
        public var avatarCornerFraction: CGFloat

        public init(page: CGFloat, avatarGap: CGFloat, avatar: CGFloat, summaryAvatar: CGFloat,
                    groupSpacing: CGFloat, messageSpacing: CGFloat, mediaWidth: CGFloat, corner: CGFloat,
                    avatarCornerFraction: CGFloat = 0.225) {
            self.mediaWidth = mediaWidth
            self.corner = corner
            self.avatarCornerFraction = avatarCornerFraction
            self.page = page
            self.avatarGap = avatarGap
            self.avatar = avatar
            self.summaryAvatar = summaryAvatar
            self.groupSpacing = groupSpacing
            self.messageSpacing = messageSpacing
        }
    }

    public var colors: Colors
    public var fonts: Fonts
    public var metrics: Metrics

    public init(colors: Colors, fonts: Fonts, metrics: Metrics) {
        self.colors = colors
        self.fonts = fonts
        self.metrics = metrics
    }

    /// The style in use. `ChatKitTheme.apply(_:)` sets it at app start.
    @MainActor static var current = ChatKitStyle.fallback

    /// Values from the design proposal, used only if the app never applies its theme.
    static let fallback = ChatKitStyle(
        colors: Colors(accent: Color(red: 0.06, green: 0.49, blue: 0.47),
                       accentBright: Color(red: 0.08, green: 0.59, blue: 0.57),
                       accentSoft: Color(red: 0.90, green: 0.96, blue: 0.95),
                       highlight: Color(red: 0.92, green: 0.41, blue: 0.43),
                       highlightSoft: Color(red: 0.99, green: 0.93, blue: 0.93),
                       ink: .primary, ink2: .secondary, ink3: Color(.tertiaryLabel),
                       background: Color(.systemBackground), surface: Color(.secondarySystemBackground),
                       line: Color(.separator), avatars: [.teal, .gray]),
        fonts: Fonts(senderName: .system(size: 16, weight: .bold), time: .system(size: 13),
                     threadSummary: .system(size: 15, weight: .semibold), threadPreview: .system(size: 15),
                     roomTitle: .system(size: 17, weight: .bold), roomSubtitle: .system(size: 13),
                     dayDivider: .system(size: 13, weight: .semibold)),
        metrics: Metrics(page: 16, avatarGap: 12, avatar: 40, summaryAvatar: 20, groupSpacing: 16, messageSpacing: 16,
                         mediaWidth: 280, corner: 12)
    )
}

public extension EnvironmentValues {
    /// True where the app draws its own header above a thread (the article discussion): the
    /// thread screen then shows no "Thread" title of its own.
    @Entry var chatThreadHeaderHidden = false
    /// The room screen under the app's room bar: the bar names the room, the title stays the app's.
    @Entry var chatRoomHeaderHidden = false
}
