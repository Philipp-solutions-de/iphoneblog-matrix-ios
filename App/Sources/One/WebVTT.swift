import Foundation

/// A WebVTT file's cues. AVPlayer shows no sidecar VTT with an MP4 and there is no HLS
/// (ADR-0005), so the app draws captions itself (spec-ios.md "Player"). Tags such as <v Name>,
/// <i> or <c.x> are dropped; positioning settings are ignored.
struct WebVTT: Equatable {
    struct Cue: Equatable {
        let start: Double
        let end: Double
        let text: String
    }

    let cues: [Cue]

    init(_ text: String) {
        var cues: [Cue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = Self.seconds(parts[0]),
                  let end = Self.seconds(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: Self.plain(body)))
        }
        self.cues = cues.sorted { $0.start < $1.start }
    }

    /// The cue on screen at a time; the latest started one when cues overlap.
    func cue(at time: Double) -> Cue? {
        cues.last { $0.start <= time && time < $0.end }
    }

    /// "00:01:02.500" or "01:02.500".
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func plain(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
