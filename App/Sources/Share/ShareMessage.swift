import Foundation

/// What the share extension posts, as plain Matrix events any client reads: an `m.text` with
/// the words and the link, and one `m.image` per picture (the words as the first picture's
/// caption, MSC2530 / spec 1.10). Web pages, links, text and pictures; no videos (Thorsten,
/// 2026-11-26 22:02: "Webseiten, Bilder, text, links").
enum ShareMessage {
    /// The text message: what the member wrote, then the link unless the words already hold it.
    /// Nil when there is nothing to send.
    static func text(words: String, link: URL?) -> String? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !words.isEmpty { parts.append(words) }
        if let link, !words.contains(link.absoluteString) { parts.append(link.absoluteString) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// `m.text` content as JSON for `Room.sendRaw`.
    static func textContent(_ body: String) -> String {
        json(["msgtype": "m.text", "body": body])
    }

    /// A picture uploaded to `url` (mxc). With a caption the body is the caption and the file
    /// name goes in `filename`; without one the body is the file name, as clients expect.
    struct Image: Equatable {
        var url: String
        var mimeType: String
        var fileName: String
        var size: Int
        var width: Int
        var height: Int
    }

    static func imageContent(_ image: Image, caption: String?) -> String {
        var content: [String: Any] = [
            "msgtype": "m.image",
            "url": image.url,
            "info": ["mimetype": image.mimeType, "size": image.size, "w": image.width, "h": image.height]
        ]
        let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if caption.isEmpty {
            content["body"] = image.fileName
        } else {
            content["body"] = caption
            content["filename"] = image.fileName
        }
        return json(content)
    }

    /// Only web links are shared as links; a file URL from Files or another app is not one.
    static func webLink(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Text that is only a web link becomes the link (Notes, Messages and others share links
    /// as text).
    static func link(inText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace) else { return nil }
        return webLink(URL(string: trimmed))
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
