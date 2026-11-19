//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// What the composer sends when a message mentions someone. Element X passes the composer's
// markdown on as `body`, so a mention left as "Hey [Dominic](https://matrix.to/#/@dominic:…)"
// (Thorsten's message, 2026-11-16). The spec wants plain text in `body` and the link only in
// `formatted_body`: `plainBody` and `html` give both; TimelineProxy (patch) uses them.

import Foundation

nonisolated public enum ComposerText {
    private static let mention = #"\[([^\]]+)\]\((https://matrix\.to/#/[^)\s]+)\)"#

    /// Whether the markdown holds a mention link.
    public static func hasMention(_ markdown: String) -> Bool {
        markdown.range(of: mention, options: .regularExpression) != nil
    }

    /// `body`: the mention as its name ("Dominic", or "@Dominic" when written so); everything
    /// else as typed.
    public static func plainBody(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: mention, with: "$1", options: .regularExpression)
    }

    /// The user IDs the markdown's mention links point at, in order, each once.
    public static func mentionedUserIDs(_ markdown: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\]\(https://matrix\.to/#/(@[^)/?\s]+)\)"#) else { return [] }
        var seen = Set<String>(), result: [String] = []
        for match in regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)) {
            guard let range = Range(match.range(at: 1), in: markdown) else { continue }
            let id = String(markdown[range]).removingPercentEncoding ?? String(markdown[range])
            if seen.insert(id).inserted { result.append(id) }
        }
        return result
    }

    /// A picture's caption as the composer's message is sent: plain `body`, `formatted_body` only
    /// when it mentions someone, and the people it mentions (Philip, 2026-11-18: a mention in a
    /// caption reached nobody). Nil for no caption.
    public static func caption(_ markdown: String?) -> (body: String, html: String?, userIDs: [String])? {
        guard let markdown, !markdown.isEmpty else { return nil }
        guard hasMention(markdown) else { return (markdown, nil, []) }
        return (plainBody(markdown), html(markdown), mentionedUserIDs(markdown))
    }

    /// `formatted_body` for the composer's inline markdown: mentions and links as <a>, **bold**,
    /// *italic* or _italic_, `code`, line breaks. Text is escaped first.
    public static func html(_ markdown: String) -> String {
        var text = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, with: "<a href=\"$2\">$1</a>",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*\*(?=\S)([^*\n]+?)(?<=\S)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "<em>$1</em>", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#, with: "<em>$1</em>", options: .regularExpression)
        return text.replacingOccurrences(of: "\n", with: "<br>")
    }
}

/// The composer's text with its pills written out as markdown links, as Element X's plain
/// composer sends a message (ComposerToolbarViewModel.plainComposerContent); for a caption.
nonisolated enum ComposerPills {
    static func markdown(_ text: NSAttributedString) -> String {
        let string = NSMutableAttributedString(attributedString: text)
        var again = true
        while again {
            again = false
            string.enumerateAttribute(.link, in: NSRange(location: 0, length: string.length)) { value, range, stop in
                guard let value else { return }
                string.removeAttribute(.link, range: range)
                if let userID = string.attribute(.MatrixUserID, at: range.location, effectiveRange: nil) as? String {
                    let name = string.attribute(.MatrixUserDisplayName, at: range.location, effectiveRange: nil) as? String
                    string.replaceCharacters(in: range, with: "[\(name ?? userID)](\(value))")
                    again = true
                    stop.pointee = true
                }
            }
        }
        return string.string
    }
}
