import SwiftUI
import UIKit

/// A small readout of the frames the screen actually draws, for proving 120 Hz on a ProMotion
/// iPhone (docs/performance.md). Off by default. A three-finger double tap anywhere turns it on
/// and off, in every build, so a TestFlight tester can read it; `IPHONEBLOG_FPS=1` in the launch
/// environment turns it on from the start (UI tests, Xcode).
///
/// It shows three numbers: the screen's maximum (`UIScreen.maximumFramesPerSecond`, 120 on a
/// ProMotion iPhone only when Info.plist carries `CADisableMinimumFrameDurationOnPhone`), the
/// frames drawn in the last second, and the longest frame of that second in milliseconds. While it
/// runs, its display link asks for up to 120 Hz, as a scrolling list does; that is the point: it
/// shows what the app may reach.
@MainActor
final class FrameRateOverlay {
    static let shared = FrameRateOverlay()

    private var window: UIWindow?
    private var label: UILabel?
    private var link: CADisplayLink?
    private var frames = 0
    private var windowStart: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var longest: CFTimeInterval = 0
    private weak var scene: UIWindowScene?

    /// **Totals since the readout appeared, for the performance tests.** A frame is late when it
    /// arrives more than half a frame after its slot; its hitch time is how late, as Apple counts
    /// it. **Only frames while something scrolls count**, as in Apple's scroll hitch ratio: a
    /// frame counts when a scroll view moved during it or in the frame before. Without that, the
    /// time XCUITest itself takes on the main thread between two swipes reads as a hitch.
    ///
    /// The totals go to the file `IPHONEBLOG_PERF_STATS` names, every 0.1 s, off the main
    /// thread; `HitchMetric` in Tests/PerfTests reads it before and after each measured block.
    /// A file and not the accessibility tree: reading the tree makes XCUITest snapshot the whole
    /// app on its main thread, the very thing being measured (docs/performance.md).
    private var totalSeconds: CFTimeInterval = 0
    private var totalHitch: CFTimeInterval = 0
    private var totalFrames = 0
    private var lateFrames = 0
    private var expected: CFTimeInterval = 1.0 / 120
    private var lastPublish: CFTimeInterval = 0
    private var scrollFrames = 0
    private var scrollSeconds: CFTimeInterval = 0
    private let statsURL = ProcessInfo.processInfo.environment["IPHONEBLOG_PERF_STATS"].map { URL(fileURLWithPath: $0) }
    private static let writer = DispatchQueue(label: "perf.stats", qos: .utility)

    private init() {}

    /// Called once per scene, from `RootView`. Adds the gesture and, if asked, shows the readout.
    func attach(to scene: UIWindowScene) {
        guard self.scene !== scene else { return }
        self.scene = scene
        if let key = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
            let tap = UITapGestureRecognizer(target: self, action: #selector(toggle))
            tap.numberOfTouchesRequired = 3
            tap.numberOfTapsRequired = 2
            tap.cancelsTouchesInView = false
            key.addGestureRecognizer(tap)
        }
        if ProcessInfo.processInfo.environment["IPHONEBLOG_FPS"] == "1" { show() }
    }

    @objc private func toggle() {
        if window == nil { show() } else { hide() }
    }

    private func show() {
        guard let scene, window == nil else { return }
        let overlay = PassthroughWindow(windowScene: scene)
        overlay.windowLevel = .statusBar + 1
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.accessibilityIdentifier = "perf-fps"
        label.text = "– fps"
        overlay.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            label.widthAnchor.constraint(equalToConstant: 168),
            label.heightAnchor.constraint(equalToConstant: 22),
        ])
        overlay.isHidden = false
        window = overlay
        self.label = label

        ScrollWatch.install()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        frames = 0
        windowStart = 0
        last = 0
        longest = 0
    }

    private func hide() {
        link?.invalidate()
        link = nil
        window?.isHidden = true
        window = nil
        label = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if windowStart == 0 { windowStart = now; last = now; return }
        frames += 1
        let interval = now - last
        longest = max(longest, interval)
        last = now
        totalFrames += 1
        totalSeconds += interval
        let moved = ScrollWatch.lastMove
        if moved >= now - interval - expected * 2 {
            scrollFrames += 1
            scrollSeconds += interval
            if interval > expected * 1.5 {
                lateFrames += 1
                totalHitch += interval - expected
            }
        }
        // The slot the next frame is due in: 8.3 ms at 120 Hz, 16.7 ms at 60.
        expected = max(1.0 / 120, link.targetTimestamp - link.timestamp)
        if let statsURL, now - lastPublish >= 0.1 {
            lastPublish = now
            let line = String(format: "{\"frames\":%d,\"scroll_frames\":%d,\"late\":%d,\"hitch_ms\":%.2f,\"scroll_seconds\":%.4f,\"seconds\":%.4f,\"max_fps\":%d}\n",
                              totalFrames, scrollFrames, lateFrames, totalHitch * 1000, scrollSeconds, totalSeconds,
                              scene?.screen.maximumFramesPerSecond ?? 0)
            Self.writer.async { try? Data(line.utf8).write(to: statsURL, options: .atomic) }
        }
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }
        let fps = Double(frames) / elapsed
        let maxFPS = scene?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        label?.text = String(format: "max %d · %.0f fps · %.1f ms", maxFPS, fps, longest * 1000)
        frames = 0
        windowStart = now
        longest = 0
    }
}

/// When a scroll view last moved, any scroll view: the table, the thread, the web view's.
/// `setContentOffset:` is swapped for a version that notes the time and calls the original; it
/// is installed only when the readout shows, never in a normal launch.
@MainActor
enum ScrollWatch {
    static var lastMove: CFTimeInterval = 0
    private static var installed = false

    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(UIScrollView.self, #selector(setter: UIScrollView.contentOffset)),
              let noting = class_getInstanceMethod(UIScrollView.self, #selector(UIScrollView.perf_setContentOffset(_:)))
        else { return }
        method_exchangeImplementations(original, noting)
        installed = true
    }
}

extension UIScrollView {
    @objc dynamic func perf_setContentOffset(_ offset: CGPoint) {
        if offset != contentOffset { MainActor.assumeIsolated { ScrollWatch.lastMove = CACurrentMediaTime() } }
        perf_setContentOffset(offset) // the original, after the swap
    }
}

/// A window that never takes a touch, so the readout cannot get in the way.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Finds the scene the SwiftUI view lives in and hands it to the overlay and the metrics.
struct PerfInstrumentsHook: UIViewRepresentable {
    func makeUIView(context: Context) -> HookView { HookView() }
    func updateUIView(_ uiView: HookView, context: Context) {}

    final class HookView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else { return }
            MainActor.assumeIsolated {
                FrameRateOverlay.shared.attach(to: scene)
            }
        }
    }
}
