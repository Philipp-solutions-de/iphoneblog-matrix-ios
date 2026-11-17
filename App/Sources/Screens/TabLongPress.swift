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

    final class HookView: UIView {
        var index = 0
        var action: () -> Void = {}
        private weak var bar: UITabBar?
        private var recognizer: UILongPressGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        func attach() {
            guard let window, bar == nil, let tabBar = Self.tabBar(in: window) else { return }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.minimumPressDuration = 0.5
            tabBar.addGestureRecognizer(press)
            bar = tabBar
            recognizer = press
        }

        @objc private func pressed(_ press: UILongPressGestureRecognizer) {
            guard press.state == .began, let bar, let count = bar.items?.count, count > 0 else { return }
            let slot = Int(press.location(in: bar).x / (bar.bounds.width / CGFloat(count)))
            guard slot == index else { return }
            action()
        }

        private static func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews { if let bar = tabBar(in: sub) { return bar } }
            return nil
        }
    }
}
