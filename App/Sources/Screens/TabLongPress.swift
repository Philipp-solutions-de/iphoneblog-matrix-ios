import SwiftUI
import UIKit

/// A long press on one tab of the tab bar (Thorsten, 2026-11-17: on "Für dich", everything
/// read). SwiftUI's tab items take no gestures, so this finds the window's UITabBar and adds a
/// long-press recognizer that reacts only over that tab.
struct TabLongPress: UIViewRepresentable {
    /// The tab's position in the bar, counted from 0.
    let index: Int
    let action: () -> Void

    func makeUIView(context: Context) -> HookView { HookView() }

    func updateUIView(_ view: HookView, context: Context) {
        view.index = index
        view.action = action
        view.attach()
    }

    final class HookView: UIView, UIGestureRecognizerDelegate {
        var index = 0
        var action: () -> Void = {}
        private weak var hookedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        /// On the window, so it works whenever the tab bar appears; it reacts only to a press
        /// that starts on the tab bar, over this tab.
        func attach() {
            guard let window, hookedWindow !== window else { return }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.minimumPressDuration = 0.5
            press.cancelsTouchesInView = false
            press.delegate = self
            window.addGestureRecognizer(press)
            hookedWindow = window
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func pressed(_ press: UILongPressGestureRecognizer) {
            guard press.state == .began, let window = hookedWindow, let bar = Self.tabBar(from: window.rootViewController),
                  let count = bar.items?.count, count > 0 else { return }
            let point = press.location(in: bar)
            guard bar.bounds.contains(point) else { return }
            let slot = Int(point.x / (bar.bounds.width / CGFloat(count)))
            guard slot == index else { return }
            action()
        }

        /// The tab bar of the tab bar controller SwiftUI's TabView builds.
        private static func tabBar(from controller: UIViewController?) -> UITabBar? {
            guard let controller else { return nil }
            if let tabs = controller as? UITabBarController { return tabs.tabBar }
            for child in controller.children { if let bar = tabBar(from: child) { return bar } }
            return tabBar(from: controller.presentedViewController)
        }
    }
}
