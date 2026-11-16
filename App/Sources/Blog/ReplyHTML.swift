import Foundation
import SwiftUI

/// A reply's `formatted_body` for readers who are not signed in. The server sanitizes it with
/// the website's allowlist (2026-11-14_interfaces.md): paragraphs, line breaks, lists, bold,
/// italic, strikethrough, code, quotes, links (http, https, mailto) and a person as
/// `<span class="pill">@Name</span>`. This turns exactly that into an AttributedString; any other
/// tag is dropped and its text kept. No WebKit: nothing loads, and it runs on any thread.
enum ReplyHTML {
    static func attributed(_ html: String) -> AttributedString {
        var parser = Parser()
        parser.run(html)
        var result = parser.output
        // Trailing blank lines from the last paragraph or list.
        while result.characters.last == "\n" {
            result.removeSubrange(result.characters.index(before: result.characters.endIndex)..<result.endIndex)
        }
        ReplyText.linkAddresses(in: &result)
        return result
    }

    private struct Parser {
        var output = AttributedString()
        private var bold = 0, italic = 0, code = 0, strike = 0, quote = 0, pill = 0
        private var links: [URL?] = []
        private var lists: [(ordered: Bool, next: Int)] = []
        private var spans: [Bool] = [] // whether each open <span> is a pill
        /// A quote's bar goes before its first text, after any paragraph inside it opened.
        private var quoteMarkPending = false

        mutating func run(_ html: String) {
            var rest = Substring(html)
            while let open = rest.firstIndex(of: "<") {
                text(String(rest[..<open]))
                guard let close = rest[open...].firstIndex(of: ">") else { text(String(rest[open...])); return }
                tag(String(rest[rest.index(after: open)..<close]))
                rest = rest[rest.index(after: close)...]
            }
            text(String(rest))
        }

        private mutating func text(_ raw: String) {
            // Line breaks between block tags are source layout, not text.
            guard !raw.isEmpty, !(raw.contains("\n") && raw.allSatisfy(\.isWhitespace)) else { return }
            if quoteMarkPending {
                quoteMarkPending = false
                var mark = AttributedString("▎")
                mark.foregroundColor = Theme.ink3
                output += mark
            }
            var piece = AttributedString(Self.decodeEntities(raw))
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if code > 0 { intent.insert(.code) }
            if strike > 0 { intent.insert(.strikethrough) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link = links.last(where: { $0 != nil }) ?? nil {
                piece.link = link
                piece.foregroundColor = Theme.teal
            }
            if pill > 0 {
                piece.foregroundColor = Theme.teal
                piece.backgroundColor = Theme.tealSoft
            }
            if quote > 0 { piece.foregroundColor = Theme.ink3 }
            output += piece
        }

        private mutating func tag(_ raw: String) {
            let closing = raw.hasPrefix("/")
            let body = closing ? raw.dropFirst() : Substring(raw)
            let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()
            switch (name, closing) {
            case ("strong", false), ("b", false): bold += 1
            case ("strong", true), ("b", true): bold = max(0, bold - 1)
            case ("em", false), ("i", false): italic += 1
            case ("em", true), ("i", true): italic = max(0, italic - 1)
            case ("code", false): code += 1
            case ("code", true): code = max(0, code - 1)
            case ("del", false), ("s", false): strike += 1
            case ("del", true), ("s", true): strike = max(0, strike - 1)
            case ("a", false): links.append(Self.href(in: String(body)))
            case ("a", true): _ = links.popLast()
            case ("span", false):
                let isPill = body.contains("pill")
                spans.append(isPill)
                if isPill { pill += 1 }
            case ("span", true):
                if spans.popLast() == true { pill = max(0, pill - 1) }
            case ("br", _): newline()
            case ("p", false), ("pre", false): blockStart()
            case ("p", true), ("pre", true): blockEnd()
            case ("blockquote", false):
                blockStart()
                quote += 1
                quoteMarkPending = true
            case ("blockquote", true):
                quote = max(0, quote - 1)
                blockEnd()
            case ("ul", false): blockStart(); lists.append((false, 1))
            case ("ol", false): blockStart(); lists.append((true, 1))
            case ("ul", true), ("ol", true):
                _ = lists.popLast()
                if lists.isEmpty { blockEnd() }
            case ("li", false):
                blockStart()
                let depth = max(0, lists.count - 1)
                let marker: String
                if var list = lists.popLast() {
                    marker = list.ordered ? "\(list.next)." : "•"
                    list.next += 1
                    lists.append(list)
                } else {
                    marker = "•"
                }
                output += AttributedString(String(repeating: "    ", count: depth) + marker + " ")
            default: break
            }
        }

        private mutating func newline() { output += AttributedString("\n") }

        /// A block starts on a new line.
        private mutating func blockStart() {
            if let last = output.characters.last, last != "\n" { newline() }
        }

        /// A paragraph or list ends with a blank line before the next block.
        private mutating func blockEnd() {
            blockStart()
            if !output.characters.isEmpty, !String(output.characters).hasSuffix("\n\n") { newline() }
        }

        static func href(in tag: String) -> URL? {
            guard let range = tag.range(of: #"href\s*=\s*"([^"]*)""#, options: .regularExpression) else { return nil }
            let value = tag[range].split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false)
            guard value.count > 1, let url = URL(string: decodeEntities(String(value[1]))),
                  ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return url
        }

        static func decodeEntities(_ text: String) -> String {
            guard text.contains("&") else { return text }
            var result = ""
            var rest = Substring(text)
            while let amp = rest.firstIndex(of: "&") {
                result += rest[..<amp]
                let after = rest[amp...]
                if let semi = after.firstIndex(of: ";"), after.distance(from: amp, to: semi) <= 10 {
                    let entity = after[after.index(after: amp)..<semi]
                    if let decoded = decode(entity) {
                        result += decoded
                        rest = after[after.index(after: semi)...]
                        continue
                    }
                }
                result += "&"
                rest = after.dropFirst()
            }
            return result + rest
        }

        private static func decode(_ entity: Substring) -> String? {
            switch entity {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos", "#39": return "'"
            case "nbsp": return "\u{00A0}"
            default:
                let hex = entity.hasPrefix("#x") || entity.hasPrefix("#X")
                guard entity.hasPrefix("#"),
                      let value = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                      let scalar = Unicode.Scalar(value) else { return nil }
                return String(Character(scalar))
            }
        }
    }
}
