//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// A warning before a message with an email address or a phone number goes out (Thorsten,
// 2026-11-17): everyone in the room reads it, and a chat is no place for contact details by
// accident. The composer (ComposerToolbarViewModel patch) asks here before it sends; contact
// details for one person go through "Kontaktdaten teilen" instead.

import UIKit

public enum ChatContactWarning {
    /// The email addresses and phone numbers in a message, as written. A phone number starts
    /// with + or 0 and has at least 8 digits, so a year, a price or a long count is not one.
    public static func contactData(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [(Int, String)] = []
        for regex in [email, phone] {
            for match in regex.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let value = String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
                if regex === phone, value.filter(\.isNumber).count < 8 || isDate(value) { continue }
                found.append((match.range.location, value))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// 01.12.2026 or 01/12/2026: a date, not a number to call.
    private static func isDate(_ value: String) -> Bool {
        value.range(of: #"^\d{1,2}[./]\d{1,2}[./]\d{2,4}$"#, options: .regularExpression) != nil
    }

    // swiftlint:disable force_try
    private static let email = try! NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                                        options: [.caseInsensitive])
    /// +49 170 1234567, 0170/1234567, 089-123 456 78, (0)89 12345678.
    private static let phone = try! NSRegularExpression(pattern: #"(?<![\w+])(?:\+|0)[0-9()][0-9 ()/.\-]{6,}[0-9]"#)
    // swiftlint:enable force_try

    /// Asks before sending; true sends. Names what was found so the writer sees it at once.
    @MainActor
    static func confirm(_ found: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let list = found.map { "„\($0)“" }.joined(separator: ", ")
            // The chat server stores email addresses in messages masked (a***@***.de), so an
            // address sent this way does not even arrive as written.
            let masked = found.contains { $0.contains("@") }
                ? " E-Mail-Adressen zeigt der Chat nur unkenntlich (a***@***.de)." : ""
            let alert = UIAlertController(
                title: "Kontaktdaten senden?",
                message: "Deine Nachricht enthält \(list). Alle in diesem Raum können sie lesen.\(masked) "
                    + "Für eine Person allein: lange auf ihren Namen drücken, dann „Kontaktdaten teilen“.",
                preferredStyle: .alert)
            alert.view.accessibilityIdentifier = "contact-warning"
            alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "Trotzdem senden", style: .destructive) { _ in continuation.resume(returning: true) })
            guard let top = topViewController() else {
                continuation.resume(returning: true)
                return
            }
            top.present(alert, animated: true)
        }
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
