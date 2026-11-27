import Foundation

/// The #one rooms the share extension offers (Thorsten, 2026-11-26: the app in the share
/// sheet, "mit Raumauswahl"). The app writes them after every fresh look at the server, beside
/// its WarmStart; the extension only reads them, so it needs no sync and no room list of its own.
/// Room IDs and names only, in the app group's defaults, which both targets share.
struct ShareTargets: Codable, Equatable {
    struct Room: Codable, Equatable, Identifiable {
        let id: String
        var name: String
    }

    /// The account the list belongs to: a list from another account is never offered.
    var userID: String
    /// The #one rooms this account may write in, in the order #one lists them.
    var rooms: [Room]

    private static let key = "shareTargets"
    private static let lastRoomKey = "shareTargets.lastRoom"

    /// The app group's defaults; the app's own where no group exists (unsigned test builds).
    static var defaults: UserDefaults { UserDefaults(suiteName: Brand.appGroupID) ?? .standard }

    static func load(for userID: String, from defaults: UserDefaults = defaults) -> ShareTargets? {
        guard let data = defaults.data(forKey: key),
              let targets = try? JSONDecoder().decode(ShareTargets.self, from: data),
              targets.userID == userID else { return nil }
        return targets
    }

    func save(to defaults: UserDefaults = Self.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        if defaults.data(forKey: Self.key) != data { defaults.set(data, forKey: Self.key) }
    }

    static func forget(in defaults: UserDefaults = defaults) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: lastRoomKey)
    }

    /// The room shared to last, so the next share starts there.
    static func lastRoomID(in defaults: UserDefaults = defaults) -> String? {
        defaults.string(forKey: lastRoomKey)
    }

    static func remember(roomID: String, in defaults: UserDefaults = defaults) {
        defaults.set(roomID, forKey: lastRoomKey)
    }

    /// The room a new share starts in: the last one shared to while it is still offered, else
    /// the first (#one-Chat, as #one lists it).
    func preselected(last: String?) -> Room? {
        rooms.first { $0.id == last } ?? rooms.first
    }

    /// The rooms of #one a member writes in: joined, and not locked.
    static func rooms(from oneRooms: [(id: String, name: String, locked: Bool)], joined: Set<String>) -> [Room] {
        oneRooms.filter { !$0.locked && joined.contains($0.id) }.map { Room(id: $0.id, name: $0.name) }
    }
}
