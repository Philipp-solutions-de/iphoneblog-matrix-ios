import MatrixRustSDK
import SwiftUI

/// A person's profile picture, else their initials (Thorsten, 2026-11-17: @Mentions showed only
/// letters although Dominic had a picture). For our own lists (@Mentions, search, profile, and
/// the coming "Für dich"); the timeline and threads draw Element X's avatars themselves.
struct MemberAvatar: View {
    let userID: String
    let name: String
    /// The room the person was seen in: its member event is the picture's freshest source.
    var roomID: String?
    var size: CGFloat = Theme.Size.chatAvatar
    var corner: CGFloat?

    @State private var image: UIImage?

    /// UI tests check that a picture loaded (IPHONEBLOG_EXPOSE_AVATARS=1, debug builds only);
    /// VoiceOver never reads avatars.
    private static var exposedForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["IPHONEBLOG_EXPOSE_AVATARS"] == "1"
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: corner ?? size / 2))
                    .accessibilityHidden(!Self.exposedForTests)
                    .accessibilityIdentifier("avatar-image")
            } else {
                InitialsAvatar(name: name, size: size, corner: corner)
            }
        }
        .task(id: userID) { image = await AvatarStore.shared.image(for: userID, in: roomID, size: size) }
    }
}

/// Finds and keeps profile pictures. The address comes from the room member (sync keeps the
/// m.room.member state current, so a new picture shows as soon as it is synced), else from the
/// profile (looked up again after five minutes). Thumbnails are kept by address, so a changed
/// picture is a new address and loads anew.
@MainActor
final class AvatarStore {
    static let shared = AvatarStore()
    var client: Client?

    private var profileURLs: [String: (url: String?, at: Date)] = [:]
    private var images: [String: UIImage] = [:]
    private static let profileLifetime: TimeInterval = 300

    func image(for userID: String, in roomID: String?, size: CGFloat) async -> UIImage? {
        guard let client, let url = await avatarURL(for: userID, in: roomID, client: client) else { return nil }
        if let cached = images[url] { return cached }
        let pixels = UInt64(size * 3)
        guard let source = try? MediaSource.fromUrl(url: url),
              let data = try? await client.getMediaThumbnail(mediaSource: source, width: pixels, height: pixels),
              let image = UIImage(data: data) else { return nil }
        images[url] = image
        return image
    }

    private func avatarURL(for userID: String, in roomID: String?, client: Client) async -> String? {
        if let roomID, let room = try? client.getRoom(roomId: roomID),
           let member = try? await room.member(userId: userID) {
            return member.avatarUrl
        }
        if let known = profileURLs[userID], Date().timeIntervalSince(known.at) < Self.profileLifetime {
            return known.url
        }
        let url = (try? await client.getProfile(userId: userID))?.avatarUrl
        profileURLs[userID] = (url, Date())
        return url
    }

    /// Signing out: nothing of the last account stays.
    func reset() {
        client = nil
        profileURLs = [:]
        images = [:]
    }
}
