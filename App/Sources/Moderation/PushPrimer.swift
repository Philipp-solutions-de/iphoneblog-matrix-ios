import SwiftUI
import UserNotifications

/// Asks for push permission where it makes sense: on the first visit to #one-Chat, after one
/// sentence on what is pushed, not the moment sign-in ends (App Review asks for permission
/// requests in context; Human Interface Guidelines, "Requesting permission").
enum PushPrimer {
    static let askedKey = "pushPrimerShown"

    /// Show the primer only when iOS has not been asked yet and the primer was not dismissed.
    static func shouldShow(status: UNAuthorizationStatus, alreadyShown: Bool) -> Bool {
        status == .notDetermined && !alreadyShown
    }
}

/// The primer as a card at the top of #one-Chat.
struct PushPrimerCard: View {
    /// Ask iOS (UNUserNotificationCenter.requestAuthorization), then register.
    let allow: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mitteilungen")
                .font(Theme.Font.name).foregroundStyle(Theme.ink)
            Text("Wir melden dir neue Artikel, Antworten auf deine Beiträge und @Mentions. Was genau, stellst du unter Ich ein.")
                .font(Theme.Font.footnote).foregroundStyle(Theme.ink2)
            HStack {
                Button(action: allow) {
                    Text("Erlauben").padding(.horizontal, 18).frame(minHeight: 40)
                }
                    .buttonStyle(FilledButton(fill: Theme.button))
                    .accessibilityIdentifier("pushPrimer.allow")
                Button("Später", action: later)
                    .foregroundStyle(Theme.teal)
                    .padding(.leading, 8)
            }
        }
        .padding(14)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.Size.corner))
        .padding(.horizontal, Theme.Space.page)
    }
}
