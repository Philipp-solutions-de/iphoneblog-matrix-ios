import Foundation

/// Where each video stopped, on this device only (spec-ios.md "Progress"; no personal data on
/// the server, Thorsten 2026-11-19). Keyed by video_id. Finished at 95 % or more.
@MainActor
final class PlaybackProgress: ObservableObject {
    struct Entry: Codable, Equatable {
        var position: Double
        var duration: Double
        var finished: Bool

        /// 0…1 for the bar.
        var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
        var started: Bool { !finished && position >= 1 }
    }

    static let shared = PlaybackProgress()
    @Published private(set) var entries: [String: Entry]
    private let defaults: UserDefaults
    private static let key = "one.playback"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = (defaults.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPHONEBLOG_PLAYBACK_RESET"] == "1" {
            entries = [:]
            save()
        }
        // UI tests: IPHONEBLOG_PLAYBACK_SEED="video_id=position/duration;…" sets progress before launch.
        if let seed = ProcessInfo.processInfo.environment["IPHONEBLOG_PLAYBACK_SEED"], !seed.isEmpty {
            for item in seed.split(separator: ";") {
                let parts = item.split(separator: "=")
                guard parts.count == 2, case let numbers = parts[1].split(separator: "/"), numbers.count == 2,
                      let position = Double(numbers[0]), let duration = Double(numbers[1]) else { continue }
                record(String(parts[0]), position: position, duration: duration)
            }
        }
        #endif
    }

    func entry(_ videoID: String) -> Entry? { entries[videoID] }

    func record(_ videoID: String, position: Double, duration: Double) {
        guard duration > 0, position.isFinite else { return }
        let finished = position / duration >= 0.95
        let entry = Entry(position: finished ? 0 : position, duration: duration,
                          finished: finished || entries[videoID]?.finished == true && position < 1)
        guard entries[videoID] != entry else { return }
        entries[videoID] = entry
        save()
    }

    /// "Weiter ab 6:12", "Gesehen", or nil before the first second.
    func label(_ videoID: String) -> String? {
        guard let entry = entries[videoID] else { return nil }
        if entry.finished { return "Gesehen" }
        return entry.started ? "Weiter ab \(Episode.duration(entry.position))" : nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
