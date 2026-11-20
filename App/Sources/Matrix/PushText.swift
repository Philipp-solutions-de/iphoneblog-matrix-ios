import Foundation

/// A message as plain text: the one preview helper for pushes, @Mentions, search results and
/// thread summaries (and the coming "Für dich"), whichever client wrote it. formatted_body first,
/// mentions as "@Name". The notification extension shows it; the app's tests check it. A push showed "[Philip Braeunlich](https://matrix.to/#/@…)nicht":
/// markdown, a link and a lost space. Pure Foundation, so the extension can compile it too.
enum PushText {
    /// The channel title with one "#", and "· Thread" for a reply in a thread.
    static func title(room: String, inThread: Bool) -> String {
        let channel = room.hasPrefix("#") ? room : "#\(room)"
        return inThread ? "\(channel) · Thread" : channel
    }

    /// `formatted_body` (HTML) when there is one, otherwise `body` (markdown), as plain text.
    static func plain(body: String, formattedBody: String? = nil) -> String {
        let text = formattedBody.map(fromHTML) ?? fromMarkdown(withoutReplyFallback(body))
        return text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The mentions in a message as `plain` writes them ("@Name"), in order, each once. Lets a
    /// preview mark them as the room timeline does (Philip, 2026-11-20: Für dich showed them grey).
    static func mentions(body: String, formattedBody: String? = nil) -> [String] {
        let pattern = formattedBody == nil
            ? #"\[@?([^\]]+)\]\(https://matrix\.to/#/@[^)]*\)"#
            : #"<a[^>]*href="https://matrix\.to/#/@[^"]*"[^>]*>@?([^<]*)</a>"#
        let source = formattedBody ?? body
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var names: [String] = []
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let name = "@" + decodeEntities(String(source[range])).trimmingCharacters(in: .whitespaces)
            if name.count > 1, !names.contains(name) { names.append(name) }
        }
        return names
    }

    // MARK: HTML

    static func fromHTML(_ html: String) -> String {
        var text = html
        // A mention: <a href="https://matrix.to/#/@user:server">Name</a> → "@Name".
        text = text.replacingOccurrences(of: #"<a[^>]*href="https://matrix\.to/#/@[^"]*"[^>]*>@?([^<]*)</a>"#,
                                         with: "@$1", options: .regularExpression)
        // The reply quote a client puts in front of a reply.
        text = text.replacingOccurrences(of: #"<mx-reply>.*?</mx-reply>"#, with: "",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</(p|li|blockquote|h[1-6]|pre)>"#, with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(text)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Markdown

    static func fromMarkdown(_ markdown: String) -> String {
        var text = markdown
        // [Name](https://matrix.to/#/@user) → "@Name"; a word glued to the link gets its space back.
        text = text.replacingOccurrences(of: #"\[@?([^\]]+)\]\(https://matrix\.to/#/@[^)]*\)(?=\w)"#,
                                         with: "@$1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[@?([^\]]+)\]\(https://matrix\.to/#/@[^)]*\)"#,
                                         with: "@$1", options: .regularExpression)
        // Any other link: its text; an image: nothing.
        text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)(?=\w)"#, with: "$1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Emphasis, code and strikethrough marks; headings and quote marks at line starts.
        text = text.replacingOccurrences(of: #"(\*\*|__|~~|`)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}(#{1,6}|>)\s?"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)
        return text
    }

    /// Drops the "> <@sender> …" quote a client puts before a reply's own text.
    static func withoutReplyFallback(_ body: String) -> String {
        guard body.hasPrefix("> <") else { return body }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.drop { $0.hasPrefix(">") }.drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }
}
