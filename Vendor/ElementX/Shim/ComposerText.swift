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
