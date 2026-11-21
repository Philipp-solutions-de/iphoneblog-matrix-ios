import AVKit
import SwiftUI

/// An article's video in its Blog card (Thorsten, 2026-11-20, "Play in the card";
/// blog-card-video.md): `de.iphoneblog.article.video`, which the thread files carry too.
struct CardVideo: Decodable, Equatable, Hashable {
    let id: String
    let manifestUrl: URL
    let posterUrl: URL?
    let captionsUrl: URL?
    let durationMs: Int?
    let width: Int?
    let height: Int?

    /// The original's shape, for the poster before anything loads; 16:9 without one.
    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 16 / 9 }
        return CGFloat(width) / CGFloat(height)
    }

    /// The video store's manifest: the renditions, in the website's order.
    struct Manifest: Decodable {
        struct File: Decodable {
            let name: String
            let width: Int?
            let list: Bool?
        }
        let files: [File]
    }

    /// The file for a view this many pixels wide: the smallest listed file at least that wide,
    /// else the widest; h264.mp4 when the manifest lists none (blog-card-video.md, "iOS").
    static func choose(_ manifest: Manifest, pixels: CGFloat) -> String {
        let listed = manifest.files.filter { $0.list ?? false }
        let wide = listed.filter { CGFloat($0.width ?? 0) >= pixels }.min { ($0.width ?? 0) < ($1.width ?? 0) }
        return (wide ?? listed.max { ($0.width ?? 0) < ($1.width ?? 0) })?.name ?? "h264.mp4"
    }

    /// Reads the manifest now (it changes while the encode goes on) and picks the file.
    @MainActor func file(pixels: CGFloat) async -> URL? {
        let base = manifestUrl.deletingLastPathComponent()
        var request = URLRequest(url: manifestUrl)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return base.appending(path: "h264.mp4")
        }
        return base.appending(path: Self.choose(manifest, pixels: pixels))
    }
}

/// The card's video: the poster with a play button; a tap plays it right there, with the
/// episode player's controls, picture-in-picture and drawn captions (on by default).
struct CardVideoView: View {
    let video: CardVideo
    /// The card's image, when the video has no poster of its own.
    let fallbackPoster: URL?
    @State private var player: EpisodePlayer?

    var body: some View {
        ZStack {
            if let player {
                EpisodePlayerView(model: player)
                    .accessibilityIdentifier("card.video.player")
            } else {
                Button(action: start) {
                    ZStack {
                        Rectangle().fill(Theme.surface)
                        if let poster = video.posterUrl ?? fallbackPoster {
                            AsyncImage(url: poster) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                            }
                        }
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.black.opacity(0.55), in: Circle())
                        if let ms = video.durationMs, ms > 0 {
                            Text(Episode.duration(Double(ms) / 1000))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Video abspielen")
                .accessibilityIdentifier("card.video.play")
            }
        }
        .aspectRatio(video.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.corner))
        .onDisappear { player?.stop() }
    }

    private func start() {
        let pixels = UIScreen.main.bounds.width * UIScreen.main.scale
        let model = EpisodePlayer(videoID: "card-" + video.id, durationS: video.durationMs.map { Double($0) / 1000 },
                                  captions: video.captionsUrl, progress: .shared) { [video] in
            await video.file(pixels: pixels)
        }
        player = model
        model.play()
    }
}
