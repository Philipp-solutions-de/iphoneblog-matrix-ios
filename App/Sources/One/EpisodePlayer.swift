import AVKit
import Combine
import SwiftUI

/// Plays one episode (spec-ios.md "Player"): the system controls for play, scrubbing, speed,
/// picture-in-picture, AirPlay and full screen; the app's own row for ±10 s, speed and "UT";
/// captions from captions.de.vtt, drawn by the app over the picture, inline and full screen.
@MainActor
final class EpisodePlayer: ObservableObject {
    static let speeds: [Float] = [1, 1.25, 1.5, 2]

    let episode: Episode
    let player = AVPlayer()
    @Published private(set) var started = false
    /// Not published: it moves four times a second; what the page shows (caption, labels) is.
    private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var captionsOn = true { didSet { updateCaption() } }
    @Published private(set) var speed: Float = 1
    @Published private(set) var caption: String?
    @Published private(set) var hasCaptions = false
    private var vtt: WebVTT?
    private var lastRecorded = -1
    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?
    private let progress: PlaybackProgress

    init(episode: Episode, progress: PlaybackProgress) {
        self.episode = episode
        self.progress = progress
        duration = Double(episode.durationS ?? 0)
        if let entry = progress.entry(episode.videoID), entry.started { position = entry.position }
        hasCaptions = episode.caption != nil
    }

    /// Loads the file chosen for this network, seeks to "Weiter ab", fetches the captions.
    func prepare() {
        guard player.currentItem == nil, let file = episode.file(cellular: NetworkKind.shared.cellular) else { return }
        let item = AVPlayerItem(url: file.url)
        player.replaceCurrentItem(with: item)
        if position > 0 { player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let rate = player.rate
            Task { @MainActor in
                guard let self else { return }
                if rate > 0 { self.started = true; if Self.speeds.contains(rate) { self.speed = rate } }
            }
        }
        if let caption = episode.caption {
            Task { await loadCaptions(caption.url) }
        }
    }

    func play() {
        prepare()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: speed)
        started = true
    }

    func skip(_ seconds: Double) {
        prepare()
        let target = max(0, min(position + seconds, duration > 0 ? duration : .greatestFiniteMagnitude))
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        record()
        updateCaption()
    }

    /// 1× → 1,25× → 1,5× → 2× → 1×.
    func nextSpeed() {
        let index = Self.speeds.firstIndex(of: speed) ?? 0
        speed = Self.speeds[(index + 1) % Self.speeds.count]
        player.defaultRate = speed
        if player.rate > 0 { player.rate = speed }
    }

    static func speedLabel(_ speed: Float) -> String {
        speed == 1 ? "1×" : (speed.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...2))) + "×")
    }

    /// Saves where it stands; called on every tick and when the page goes.
    func record() {
        guard duration > 0, position > 0 else { return }
        progress.record(episode.videoID, position: position, duration: duration)
    }

    func stop() {
        record()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObserver = nil
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0, itemDuration != duration { duration = itemDuration }
        // Before the first frame the player reports 0; the saved position stays until it moves.
        if seconds > 0 || started { position = seconds }
        updateCaption()
        // Saved once a second, not on every tick.
        if player.rate > 0, Int(position) != lastRecorded { lastRecorded = Int(position); record() }
    }

    private func loadCaptions(_ url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url), let text = String(data: data, encoding: .utf8) else { return }
        vtt = WebVTT(text)
        updateCaption()
    }

    private func updateCaption() {
        let text = captionsOn ? vtt?.cue(at: position)?.text : nil
        if text != caption { caption = text }
    }
}

/// The system player view, with the captions in its content overlay so they stay in full
/// screen, which turns to landscape (OrientationGate).
struct EpisodePlayerView: UIViewControllerRepresentable {
    @ObservedObject var model: EpisodePlayer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.speeds = EpisodePlayer.speeds.map { AVPlaybackSpeed(rate: $0, localizedName: EpisodePlayer.speedLabel($0)) }
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black
        let label = context.coordinator.label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.accessibilityIdentifier = "player.caption"
        label.translatesAutoresizingMaskIntoConstraints = false
        if let overlay = controller.contentOverlayView {
            overlay.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -14),
                label.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.9),
            ])
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        let label = context.coordinator.label
        let text = model.caption ?? ""
        // A little room around the words, as subtitles have.
        label.text = text.isEmpty ? nil : " \(text.replacingOccurrences(of: "\n", with: " \n ")) "
        label.isHidden = text.isEmpty
        label.accessibilityLabel = text
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let label = UILabel()

        nonisolated func playerViewController(_ controller: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            MainActor.assumeIsolated { OrientationGate.allowLandscape = true }
        }

        nonisolated func playerViewController(_ controller: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated { Self.endFullScreen() }
            }
        }

        /// Back to portrait when full screen ends.
        static func endFullScreen() {
            OrientationGate.allowLandscape = false
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

/// The app is portrait; a video in full screen may turn (spec: "full screen rotates to
/// landscape"). AppDelegate asks this.
enum OrientationGate {
    @MainActor static var allowLandscape = false
    @MainActor static var mask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return allowLandscape ? .allButUpsideDown : .portrait
    }
}

/// The players of the #one tab, one per episode while its page is open. The tab owns them and
/// re-renders when one changes, so the pushed page follows (a page that owned its player did not
/// redraw on its own changes inside the tab's NavigationStack).
@MainActor
final class EpisodePlayers: ObservableObject {
    private var players: [String: EpisodePlayer] = [:]
    private var watches: [String: AnyCancellable] = [:]

    func player(for episode: Episode) -> EpisodePlayer {
        if let known = players[episode.videoID] { return known }
        let player = EpisodePlayer(episode: episode, progress: .shared)
        players[episode.videoID] = player
        watches[episode.videoID] = player.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return player
    }

    /// The page closed: save, stop, forget.
    func close(_ episode: Episode) {
        players[episode.videoID]?.stop()
        players[episode.videoID] = nil
        watches[episode.videoID] = nil
    }
}
