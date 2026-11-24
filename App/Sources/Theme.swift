import SwiftUI
import UIKit

/// Every visual value of the app in one place: colours, type, spacing, sizes.
/// Feedback rounds change this file; screens only name what they mean (`Theme.ink`,
/// `Theme.Font.rowTitle`, `Theme.Space.row`). Values follow the approved design previews
/// ("iphoneblog App Entwürfe", Thorsten 2026-11-15: "Build that"), light and dark.
enum Theme {
    // MARK: Colours (light / dark)

    // **The #one tint** (Thorsten, 2026-11-20: "Alles was #one ist ist in dem Rot-ton. Nicht in
    // Teal."): inside the #one tab (`.oneTint`, set by OneChatGate) every teal below turns the
    // #one red, #EB686E, with no teal anywhere; outside it stays teal. Red with white text on it
    // is the darker #C4434A, as `coralButton`, so it reads at 5:1; red words are `coralText`.

    /// Buttons, links, the selected tab: teal dark enough for white text (dark: brighter).
    static let teal = dynamic(light: 0x0F7D78, dark: 0x3DB8B1, oneLight: 0xC4434A, oneDark: 0xEB686E)
    /// The blog's teal for titles and small accents.
    static let tealBright = dynamic(light: 0x149791, dark: 0x1B9791, oneLight: 0xEB686E, oneDark: 0xEB686E)
    /// Filled buttons (white text on it).
    static let button = dynamic(light: 0x0F7D78, dark: 0x1B9791, oneLight: 0xC4434A, oneDark: 0xC4434A)
    /// Unread badges on the tabs and a mention of you: white on this teal, 5:1 in both modes.
    static let badge = dynamic(light: 0x0F7D78, dark: 0x0F7D78, oneLight: 0xC4434A, oneDark: 0xC4434A)
    /// The bot marks ("Bot" pill, a bot's name): teal everywhere, inside #one too (Thorsten,
    /// 2026-11-20), so the one teal that has no #one variant.
    static let bot = dynamic(light: 0x0F7D78, dark: 0x3DB8B1)
    /// Soft teal behind a mention and the Diskussion chip.
    static let tealSoft = dynamic(light: 0xE3F2F1, dark: 0x16302F, oneLight: 0xFDECED, oneDark: 0x2E1819)
    /// The colour rule (Thorsten, 2026-11-16): teal (the blog's $linkcolor #149791) is the colour
    /// of all content: links, the active tab, unread badges and dots, reply counts, mentions,
    /// default avatars. Coral (the blog's $goldcolor #eb686e) marks only what belongs to #one,
    /// sign-in included: the Anmelden buttons, the #one-Chat lock, #one hints and upgrade
    /// links. `coral` for marks, `coralText` for coral words, `coralButton` for filled buttons.
    static let coral = dynamic(light: 0xEB686E, dark: 0xEB686E)
    static let coralText = dynamic(light: 0xC4434A, dark: 0xEF8A8F)
    static let coralButton = dynamic(light: 0xC4434A, dark: 0xC4434A)
    static let coralSoft = dynamic(light: 0xFDECED, dark: 0x2E1819)
    /// An unread mention's row: a breath of teal.
    static let unread = dynamic(light: 0xF0F8F7, dark: 0x142221, oneLight: 0xFDF3F3, oneDark: 0x241617)

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

    /// Initials avatars: one colour per name, always the same. Teal and neutral only (the colour
    /// rule above); every one carries white initials at 4.5:1 or better.
    /// Inside #one the teal ones turn red of the same weight.
    static let avatarColors: [Color] = [(0x0F7D78, 0xC4434A), (0x3A6F6C, 0x8E4A4D), (0x5C6B6A, 0x6E5E5F), (0x0B6662, 0xA3363C),
                                        (0x4F5A5C, 0x5E5455), (0x2F7F7A, 0xB04A50), (0x646464, 0x646464)]
        .map { dynamic(light: $0.0, dark: $0.0, oneLight: $0.1, oneDark: $0.1) }

    // MARK: Type (system font throughout)

    enum Font {
        static let screenTitle = SwiftUI.Font.system(size: 30, weight: .semibold)
        static let signInTitle = SwiftUI.Font.system(size: 30, weight: .semibold)
        /// "DISKUSSION", "MITTEILUNGEN": small capitals over a group.
        static let overline = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let sectionHeader = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let rowTitle = SwiftUI.Font.system(size: 16)
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
        static let chatAvatar: CGFloat = 36
        /// Every person's picture is a squircle (Philip, 2026-11-18): a rounded square with
        /// continuous corners, the radius this share of its side, close to an app icon. The web
        /// uses the same share (border-radius: 22.5%). Room icons keep their own shape.
        static let avatarCornerFraction: CGFloat = 0.225
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

    /// A colour with its #one variant: the trait decides, so SwiftUI and the UIKit parts of the
    /// conversation views (ChatKitTheme hands them UIColors made from these) agree.
    private static func dynamic(light: UInt32, dark: UInt32, oneLight: UInt32, oneDark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            if traits[OneTintTrait.self] { return UIColor(hex: isDark ? oneDark : oneLight) }
            return UIColor(hex: isDark ? dark : light)
        })
    }
}

/// True inside the #one tab: Theme's teals turn the #one red there (Theme, "The #one tint").
/// A UIKit trait bridged to SwiftUI's environment, so one `.environment(\.oneTint, true)`
/// reaches SwiftUI views, UIKit views and the colours both resolve.
struct OneTintTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
    static let name = "OneTint"
}

private struct OneTintKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = false
    static func read(from traitCollection: UITraitCollection) -> Bool { traitCollection[OneTintTrait.self] }
    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) { mutableTraits[OneTintTrait.self] = value }
}

extension EnvironmentValues {
    var oneTint: Bool {
        get { self[OneTintKey.self] }
        set { self[OneTintKey.self] = newValue }
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

/// The shape of a person's picture or initials, at any size (Theme.Size.avatarCornerFraction).
enum AvatarShape {
    static func of(_ size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size * Theme.Size.avatarCornerFraction, style: .continuous)
    }
}
