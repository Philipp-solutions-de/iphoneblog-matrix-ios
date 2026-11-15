import SwiftUI
import UIKit

/// Every visual value of the app in one place: colours, type, spacing, sizes.
/// Feedback rounds change this file; screens only name what they mean (`Theme.ink`,
/// `Theme.Font.rowTitle`, `Theme.Space.row`). Values follow the approved design previews
/// ("iphoneblog App Entwürfe", Thorsten 2026-11-15: "Build that"), light and dark.
enum Theme {
    // MARK: Colours (light / dark)

    /// Buttons, links, the selected tab: teal dark enough for white text (dark: brighter).
    static let teal = dynamic(light: 0x0F7D78, dark: 0x3DB8B1)
    /// The blog's teal for titles and small accents.
    static let tealBright = dynamic(light: 0x149791, dark: 0x1B9791)
    /// Filled buttons (white text on it).
    static let button = dynamic(light: 0x0F7D78, dark: 0x1B9791)
    /// Soft teal behind a mention and the Diskussion chip.
    static let tealSoft = dynamic(light: 0xE3F2F1, dark: 0x16302F)
    /// #one: coral. `coral` for marks and badges, `coralText` for coral words and outlines'
    /// text, `coralButton` for the filled #one button.
    static let coral = dynamic(light: 0xEB686E, dark: 0xEB686E)
    static let coralText = dynamic(light: 0xC4434A, dark: 0xEF8A8F)
    static let coralButton = dynamic(light: 0xC4434A, dark: 0xC4434A)
    static let coralSoft = dynamic(light: 0xFDECED, dark: 0x2E1819)
    /// An unread mention's row.
    static let unread = dynamic(light: 0xFDF3F3, dark: 0x1D1617)

    /// Text: headings and names, body, quiet.
    static let ink = dynamic(light: 0x111111, dark: 0xECECEC)
    static let ink2 = dynamic(light: 0x333333, dark: 0xC4C4C4)
    static let ink3 = dynamic(light: 0x6E6E6E, dark: 0x8A8A8A)

    /// Page, input fields and panels, hairlines.
    static let background = dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let surface = dynamic(light: 0xF6F6F6, dark: 0x1C1C1C)
    static let panel = dynamic(light: 0xF7F7F7, dark: 0x1B1B1B)
    static let line = dynamic(light: 0xE4E4E4, dark: 0x2A2A2A)
    /// Settings: the grouped page and its cells.
    static let group = dynamic(light: 0xF2F2F4, dark: 0x111111)
    static let cell = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// The tab bar.
    static let tabBar = dynamic(light: 0xFAFAFA, dark: 0x1A1A1A)
    /// Badge for "new, but not for you".
    static let quietBadge = dynamic(light: 0xECEFF0, dark: 0x2A2A2A)

    /// Initials avatars: one colour per name, always the same.
    static let avatarColors: [Color] = [0x3F8FA8, 0xC98A3B, 0x5B7FC7, 0x8A6BB8, 0x4F9A6A, 0xC06A4F, 0x3A7A8C].map { Color(hex: $0) }

    // MARK: Type (system font throughout)

    enum Font {
        static let screenTitle = SwiftUI.Font.system(size: 30, weight: .semibold)
        static let signInTitle = SwiftUI.Font.system(size: 30, weight: .semibold)
        /// "DISKUSSION", "MITTEILUNGEN": small capitals over a group.
        static let overline = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let sectionHeader = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let rowTitle = SwiftUI.Font.system(size: 16)
        static let rowHash = SwiftUI.Font.system(size: 19)
        static let name = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let time = SwiftUI.Font.system(size: 13)
        static let body = SwiftUI.Font.system(size: 16)
        static let reading = SwiftUI.Font.system(size: 17)
        static let footnote = SwiftUI.Font.system(size: 14)
        static let badge = SwiftUI.Font.system(size: 11, weight: .bold)
        static let button = SwiftUI.Font.system(size: 17, weight: .semibold)
    }

    // MARK: Spacing and sizes

    enum Space {
        static let page: CGFloat = 18
        static let row: CGFloat = 12
        static let rowGap: CGFloat = 11
        static let section: CGFloat = 16
    }

    enum Size {
        static let avatar: CGFloat = 34
        /// #one-Chat uses rounded squares, the discussion circles.
        static let chatAvatar: CGFloat = 36
        static let chatAvatarCorner: CGFloat = 9
        static let profileAvatar: CGFloat = 58
        static let signInLogo: CGFloat = 96
        static let rowIcon: CGFloat = 28
        static let headerAvatar: CGFloat = 36
        static let badgeHeight: CGFloat = 18
        static let unreadDot: CGFloat = 9
        static let searchHeight: CGFloat = 38
        static let buttonHeight: CGFloat = 50
        static let smallButtonHeight: CGFloat = 44
        static let corner: CGFloat = 14
        static let panelCorner: CGFloat = 18
        static let groupCorner: CGFloat = 12
        static let lockCircle: CGFloat = 76
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
