//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Bots marked as bots (Thorsten, 2026-11-17): the name in the strong teal and a teal "Bot" pill
// with a robot, only for the IDs the chat server lists (GET /_iphoneblog/v1/bots), never by a
// name that looks like one. The app fetches the list and sets `ChatKitBots.ids`.

import SwiftUI

public enum ChatKitBots {
    public static var ids: Set<String> = []
    public static func isBot(_ userID: String) -> Bool { ids.contains(userID) }
}

/// "Bot", with a small robot, in teal.
public struct ChatBotPill: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 3) {
            RobotGlyph().frame(width: 11, height: 11)
            Text("Bot").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(minHeight: 17)
        .background(ChatKitStyle.current.colors.accent, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bot")
        .accessibilityIdentifier("bot-badge")
    }
}

/// A robot head: antenna, rounded face, two eyes. Drawn here; SF Symbols has no robot.
private struct RobotGlyph: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let head = CGRect(x: w * 0.1, y: h * 0.3, width: w * 0.8, height: h * 0.62)
            context.fill(Path(roundedRect: head, cornerRadius: w * 0.18), with: .foreground)
            context.fill(Path(CGRect(x: w * 0.46, y: h * 0.08, width: w * 0.08, height: h * 0.24)), with: .foreground)
            context.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: 0, width: w * 0.24, height: h * 0.16)), with: .foreground)
            let eye = w * 0.16
            context.blendMode = .clear
            context.fill(Path(ellipseIn: CGRect(x: w * 0.27, y: h * 0.5, width: eye, height: eye)), with: .foreground)
            context.fill(Path(ellipseIn: CGRect(x: w * 0.57, y: h * 0.5, width: eye, height: eye)), with: .foreground)
        }
        .compositingGroup()
    }
}
