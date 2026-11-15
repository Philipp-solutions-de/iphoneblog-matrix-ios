import SwiftUI

/// The Blog tab's and the Diskussion view's values (design preview "Blog tab" and "Diskussion",
/// 2026-11-15). Kept beside the screens that use them; colours come from `Theme`.
extension Theme {
    enum Discussion {
        /// The logo bar above the web view.
        static let logoSize: CGFloat = 38
        static let logoBarHeight: CGFloat = 52

        static let margin: CGFloat = 18
        static let eyebrow = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// The blog sets titles in Fira Sans, light; the system's sans stands in.
        static let title = SwiftUI.Font.system(size: 22, weight: .regular)
        static let meta = SwiftUI.Font.system(size: 14)
        static let avatar: CGFloat = 34
        static let sender = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let time = SwiftUI.Font.system(size: 13)
        static let offer = SwiftUI.Font.system(size: 15)
        static let offerCorner: CGFloat = 18
        static let buttonHeight: CGFloat = 44
        /// Coral as text on the page: darker in light mode, lighter in dark, for contrast.
        static let coralText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xEF8A8F) : UIColor(hex: 0xC4434A) })
    }
}
