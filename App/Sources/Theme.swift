import SwiftUI
import UIKit

/// Every visual value of the app in one place: colours, type, spacing, sizes.
/// Feedback rounds change this file; screens only name what they mean (`Theme.ink`,
/// `Theme.Font.rowTitle`, `Theme.Space.row`). Values follow the design proposal
/// (notes folder 2026-11-14_matrix-app-design, design/screens.html in this repository).
enum Theme {
    // MARK: Colours (light / dark)
    //
    // Dark values follow the blog's dark theme (ipbmin.css, prefers-color-scheme: dark):
    // page #111, text #aeaeae, raised blocks #1e1e1e, teal #2c9e94, coral #d0666b.

    /// Buttons, links, the selected tab: the blog's teal, dark enough for white text.
    static let teal = dynamic(light: 0x0F7D78, dark: 0x2C9E94)
    /// The blog's theme colour itself, for small accents (unread dot).
    static let tealBright = dynamic(light: 0x149791, dark: 0x2C9E94)
    /// Soft teal behind a selected row or someone else's mention.
    static let tealSoft = dynamic(light: 0xE6F4F3, dark: 0x16302E)
    /// Something meant for you: mention and direct-message badges.
    static let coral = dynamic(light: 0xEB686E, dark: 0xD0666B)
    /// Soft coral behind a mention of you.
    static let coralSoft = dynamic(light: 0xFDEDEE, dark: 0x3A1E20)

    /// Text: main, secondary, faint.
    static let ink = dynamic(light: 0x1D2326, dark: 0xAEAEAE)
    static let ink2 = dynamic(light: 0x5C676C, dark: 0x8F8F8F)
    static let ink3 = dynamic(light: 0x97A1A5, dark: 0x6E6E6E)

    /// Page, raised surfaces (search field, grouped settings), hairlines.
    static let background = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let surface = dynamic(light: 0xF7F8F8, dark: 0x1E1E1E)
    static let line = dynamic(light: 0xECEFF0, dark: 0x2A2A2A)
    /// Badge for "new, but not for you".
    static let quietBadge = dynamic(light: 0xECEFF0, dark: 0x2A2A2A)

    /// Initials avatars: one colour per name, always the same.
    static let avatarColors: [Color] = [0x149791, 0xE0A43A, 0x7C6BC4, 0xEB686E, 0x4C8DC9, 0x5F8C5A].map { Color(hex: $0) }

    // MARK: Type

    enum Font {
        /// Big screen titles ("iphoneblog", "Ich"). The blog uses Foro; until the app has a
        /// licence for it, the system serif stands in.
        static let screenTitle = SwiftUI.Font.system(size: 30, weight: .bold, design: .serif)
        static let signInTitle = SwiftUI.Font.system(size: 30, weight: .bold, design: .serif)
        static let sectionHeader = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let rowTitle = SwiftUI.Font.system(size: 17)
        static let rowHash = SwiftUI.Font.system(size: 19)
        static let badge = SwiftUI.Font.system(size: 12.5, weight: .bold)
        static let body = SwiftUI.Font.system(size: 16)
        static let footnote = SwiftUI.Font.system(size: 13)
    }

    // MARK: Spacing and sizes

    enum Space {
        /// Left and right page margin.
        static let page: CGFloat = 20
        /// Vertical padding of a list row.
        static let row: CGFloat = 9
        /// Gap between a row's icon and its title.
        static let rowGap: CGFloat = 12
        /// Space above a section header.
        static let section: CGFloat = 16
    }

    enum Size {
        static let rowIcon: CGFloat = 28
        static let headerAvatar: CGFloat = 36
        static let profileAvatar: CGFloat = 84
        static let signInLogo: CGFloat = 112
        static let badgeHeight: CGFloat = 22
        static let unreadDot: CGFloat = 9
        static let searchHeight: CGFloat = 38
        static let buttonHeight: CGFloat = 52
        static let corner: CGFloat = 12
        static let groupCorner: CGFloat = 14
    }

    // MARK: Blog tab

    enum Blog {
        /// The feed: one card per article, image on top, like a social feed.
        static let title = SwiftUI.Font.system(size: 21, weight: .bold, design: .serif)
        static let teaser = SwiftUI.Font.system(size: 15.5)
        static let meta = SwiftUI.Font.system(size: 13.5)
        /// Image height as a share of the card width (16:9).
        static let imageAspect: CGFloat = 16.0 / 9.0
        static let imageCorner: CGFloat = 14
        static let cardGap: CGFloat = 28
        static let cardInnerGap: CGFloat = 10
        static let replierAvatar: CGFloat = 22
        static let maxRepliers = 3
        /// The hairline between cards.
        static let divider = Theme.line
    }

    // MARK: Locked and signed-out screens

    enum Gate {
        static let title = SwiftUI.Font.system(size: 22, weight: .bold, design: .serif)
        static let iconSize: CGFloat = 44
    }

    // MARK: Helpers

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}
