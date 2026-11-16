import Foundation
import SwiftUI

/// A reply's text for readers who are not signed in. The guest API hands out the plain `body`,
/// which carries what the writer typed: markdown and bare addresses. This shows the markdown's
/// inline parts (bold, italic, code, links), makes every address a link, and drops the quoted
/// lines a Matrix reply starts with ("> <@stefan:…> …"), which the chat shows as a quote instead.
enum ReplyText {
    /// The server's sanitized HTML when the reply has it, otherwise the plain body.
    static func attributed(body: String, formattedBody: String?) -> AttributedString {
        if let formattedBody, !formattedBody.isEmpty { return ReplyHTML.attributed(formattedBody) }
        return attributed(body)
    }

    static func attributed(_ body: String) -> AttributedString {
        let text = withoutReplyFallback(body)
        var result = (try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        ))) ?? AttributedString(text)
        linkAddresses(in: &result)
        for run in result.runs where run.link != nil {
            result[run.range].foregroundColor = Theme.teal
        }
        return result
    }

    /// Strips the leading "> " block of a reply fallback and the blank line after it.
    static func withoutReplyFallback(_ body: String) -> String {
        guard body.hasPrefix("> <") else { return body }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        let rest = lines.drop { $0.hasPrefix(">") }.drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        return rest.joined(separator: "\n")
    }

    /// Bare "https://…" and "www.…" addresses become links; markdown links stay as they are.
    static func linkAddresses(in text: inout AttributedString) {
        let plain = String(text.characters)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: plain) else { continue }
            // The same characters in both, so a character offset carries over.
            let lower = text.characters.index(text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: range.lowerBound))
            let upper = text.characters.index(lower, offsetBy: plain.distance(from: range.lowerBound, to: range.upperBound))
            if text[lower..<upper].runs.contains(where: { $0.link != nil }) { continue }
            text[lower..<upper].link = url
        }
    }
}
