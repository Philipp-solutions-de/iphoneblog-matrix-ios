//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Swipes on a message (Alex's request, approved): right answers in the thread, left offers the
// reactions. Modelled on Element X's SwipeRightAction, in both directions, with two rules of
// ours: a swipe never starts within 30 pt of the screen's left edge, where the navigation's
// swipe-back lives, and only a mostly horizontal pan begins one, so scrolling stays scrolling.
// A haptic tick at the threshold; with Reduce Motion the row does not move or spring.
// The swipe takes the whole row width, also the empty space beside a short message (approved
// 2026-11-20); taps and the long press stay on the message itself.

import SwiftUI
import UIKit

struct MessageSwipe<Leading: View, Trailing: View>: ViewModifier {
    private let actionThreshold = 50.0
    private let maxOffset = 100.0
    private let travel = 1000.0
    static var edgeMargin: CGFloat { 30 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var xOffset = 0.0
    @State private var passedThreshold = false
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    let isEnabled: () -> Bool
    /// False inside a thread (Philip, 2026-11-18): the row does not move right and shows no icon.
    var allowsRight: () -> Bool = { true }
    let leading: () -> Leading
    let trailing: () -> Trailing
    let swipedRight: () -> Void
    let swipedLeft: () -> Void

    func body(content: Content) -> some View {
        content
            // Full width for the pan alone: the message's own tap and long press sit inside, on
            // its own area, so a tap beside a short message still does nothing.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: reduceMotion ? 0 : xOffset)
            .animation(reduceMotion ? nil : .interactiveSpring().speed(0.5), value: xOffset)
            .overlay(alignment: .leading) {
                leading()
                    .frame(maxWidth: actionThreshold)
                    .opacity(max(0, xOffset) / actionThreshold)
                    .offset(x: reduceMotion ? 0 : -actionThreshold + min(max(0, xOffset), actionThreshold))
            }
            .overlay(alignment: .trailing) {
                trailing()
                    .frame(maxWidth: actionThreshold)
                    .opacity(max(0, -xOffset) / actionThreshold)
                    .offset(x: reduceMotion ? 0 : actionThreshold - min(max(0, -xOffset), actionThreshold))
            }
            .gesture(HorizontalPan(edgeMargin: Self.edgeMargin, isEnabled: isEnabled) { recognizer in
                switch recognizer.state {
                case .began:
                    feedback.prepare()
                case .ended:
                    if xOffset > actionThreshold, allowsRight() { swipedRight() }
                    if xOffset < -actionThreshold { swipedLeft() }
                    reset()
                case .cancelled, .failed:
                    reset()
                default:
                    let dx = recognizer.translation(in: nil).x
                    xOffset = MessageSwipeMath.offset(dx: dx, travel: travel, maxOffset: maxOffset, allowsRight: allowsRight())
                    let past = abs(xOffset) > actionThreshold
                    if past, !passedThreshold { feedback.impactOccurred() }
                    passedThreshold = past
                }
            })
    }

    private func reset() {
        xOffset = 0
        passedThreshold = false
    }
}

/// How far a row moves for a pan of `dx` points (MessageSwipeTests).
public enum MessageSwipeMath {
    /// Slower the further it goes (a circular ease-out, as Element X's swipe); never to the right
    /// when the right swipe is off (inside a thread), so no icon shows there.
    nonisolated public static func offset(dx: CGFloat, travel: CGFloat = 1000, maxOffset: CGFloat = 100, allowsRight: Bool) -> CGFloat {
        let normalised = max(-travel, min(dx, travel)) / travel
        let eased = sqrt((2 - abs(normalised)) * abs(normalised)) * (normalised < 0 ? -1 : 1)
        return allowsRight ? eased * maxOffset : min(0, eased * maxOffset)
    }
}

extension View {
    func messageSwipe(isEnabled: @escaping () -> Bool,
                      allowsRight: @escaping () -> Bool = { true },
                      leading: @escaping () -> some View,
                      trailing: @escaping () -> some View,
                      swipedRight: @escaping () -> Void,
                      swipedLeft: @escaping () -> Void) -> some View {
        modifier(MessageSwipe(isEnabled: isEnabled, allowsRight: allowsRight, leading: leading, trailing: trailing,
                              swipedRight: swipedRight, swipedLeft: swipedLeft))
    }
}

/// A pan that begins only when it is mostly horizontal and starts away from the left edge.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let edgeMargin: CGFloat
    let isEnabled: () -> Bool
    let handle: (UIPanGestureRecognizer) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(edgeMargin: edgeMargin, isEnabled: isEnabled)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let edgeMargin: CGFloat
        let isEnabled: () -> Bool

        init(edgeMargin: CGFloat, isEnabled: @escaping () -> Bool) {
            self.edgeMargin = edgeMargin
            self.isEnabled = isEnabled
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, isEnabled() else { return false }
            let start = pan.location(in: nil)
            let velocity = pan.velocity(in: nil)
            return start.x > edgeMargin && abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
