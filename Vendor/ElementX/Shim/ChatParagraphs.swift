import UIKit

/// Paragraphs inside a message and the break between messages (Thorsten, 2026-11-24, "Yes, both";
/// values agreed with the web, chat-web PR #23): a paragraph gets 4 pt after it, a line break
/// none, and a run of blank lines is one paragraph break. Before, a paragraph was a full empty
/// line, larger than the 4 pt between two messages of a group, so five replies read as two
/// blocks (#allgemein, 2026-11-23). The break between messages is ChatKitStyle's messageSpacing.
nonisolated enum ChatParagraphs {
    /// Space after a paragraph, in points.
    static let spacing: CGFloat = 4

    /// A line break that is not a paragraph's end: U+2028, which takes no paragraph spacing.
    static let lineBreak = "\u{2028}"

    /// A message's text for the timeline: blank-line runs become one paragraph break ("\n"),
    /// and in a plain body each remaining single newline is a line break. In HTML a `<br>` is
    /// already a line break (AttributedStringBuilder) and a `<p>` ends with "\n". Trailing breaks
    /// go, so the last paragraph adds no space below the message.
    static func normalise(_ text: NSMutableAttributedString, plain: Bool) {
        replace(#"[\n ][ \t]*(?:[\n ][ \t]*)+"#, in: text, with: "\n")
        if plain { replace(#"\n"#, in: text, with: lineBreak) }
        replace(#"[\n \s]+$"#, in: text, with: "")
    }

    /// 4 pt after every paragraph, kept with the paragraph styles the text already has.
    static func space(_ text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        var unstyled: [NSRange] = []
        text.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
            guard let style = value as? NSParagraphStyle else { unstyled.append(range); return }
            let spaced = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            spaced.paragraphSpacing = spacing
            text.addAttribute(.paragraphStyle, value: spaced, range: range)
        }
        for range in unstyled {
            let spaced = NSMutableParagraphStyle()
            spaced.paragraphSpacing = spacing
            text.addAttribute(.paragraphStyle, value: spaced, range: range)
        }
    }

    private static func replace(_ pattern: String, in text: NSMutableAttributedString, with replacement: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            text.replaceCharacters(in: match.range, with: replacement)
        }
    }
}
