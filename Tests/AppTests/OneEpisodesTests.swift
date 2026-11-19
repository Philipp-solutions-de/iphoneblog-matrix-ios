import XCTest
@testable import iphoneblog

/// The #one hub's data: the route's answer, the file choice, captions, progress
/// (spec-ios.md "Data", "Player", "Progress").
@MainActor
final class OneEpisodesTests: XCTestCase {
    private func episode(files: [(height: Int?, list: Bool, name: String)]) throws -> Episode {
        let list = files.map { #"{"url":"https://x.de/v/\#($0.name)","width":null,"height":\#($0.height.map(String.init) ?? "null"),"mime":"video/mp4","bytes":null,"list":\#($0.list)}"# }
        let json = #"{"post_id":1,"number":null,"title":"T","published":"2026-11-17T06:00:00Z","duration_s":null,"video_id":"v","poster":null,"link":null,"notes_html":null,"manifest":null,"files":[\#(list.joined(separator: ","))],"captions":[]}"#
        return try JSONDecoder().decode(Episode.self, from: Data(json.utf8))
    }

    func testFixtureDecodes() async throws {
        let page = try await FixtureEpisodesSource().page(before: nil)
        XCTAssertEqual(page.total, 525)
        XCTAssertEqual(page.next, "2026-11-03T18:30:00Z")
        XCTAssertEqual(page.episodes.map(\.number), [527, nil, 525])
        XCTAssertEqual(page.episodes[0].caption?.lang, "de")
        XCTAssertNil(page.episodes[1].poster)
        XCTAssertEqual(page.episodes[0].dateLabel, "Di., 17. Nov.")
    }

    func testFileByHeightNeverByName() throws {
        let wifi = try episode(files: [(1080, true, "remux.mp4"), (720, true, "720.mp4"), (2160, true, "2160.mp4"), (360, false, "360.mp4")])
        XCTAssertEqual(wifi.file(cellular: false)?.height, 1080)
        XCTAssertEqual(wifi.file(cellular: true)?.height, 720)
        // Only remux.mp4 listed: it plays, whatever its name.
        let only = try episode(files: [(1080, true, "remux.mp4"), (360, false, "360.mp4")])
        XCTAssertEqual(only.file(cellular: true)?.url.lastPathComponent, "remux.mp4")
        // Nothing at or below the target: the smallest listed above it.
        let big = try episode(files: [(2160, true, "a.mp4"), (1440, true, "b.mp4")])
        XCTAssertEqual(big.file(cellular: false)?.height, 1440)
        XCTAssertNil(try episode(files: [(720, false, "720.mp4")]).file(cellular: false), "an unlisted file plays")
    }

    func testDuration() {
        XCTAssertEqual(Episode.duration(372), "6:12")
        XCTAssertEqual(Episode.duration(9), "0:09")
        XCTAssertEqual(Episode.duration(3725), "1:02:05")
    }

    func testWebVTT() {
        let vtt = WebVTT("""
        WEBVTT

        1
        00:00:01.000 --> 00:00:03.500 align:center
        <v Alex>Hallo <i>du</i> &amp; ich</v>

        00:04.000 --> 00:06.000
        Zweite
        Zeile
        """)
        XCTAssertEqual(vtt.cues.count, 2)
        XCTAssertEqual(vtt.cue(at: 2)?.text, "Hallo du & ich")
        XCTAssertNil(vtt.cue(at: 3.6))
        XCTAssertEqual(vtt.cue(at: 5)?.text, "Zweite\nZeile")
    }

    func testProgressLabels() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OneEpisodesTests"))
        defaults.removePersistentDomain(forName: "OneEpisodesTests")
        let progress = PlaybackProgress(defaults: defaults)
        XCTAssertNil(progress.label("v"))
        progress.record("v", position: 372, duration: 1532)
        XCTAssertEqual(progress.label("v"), "Weiter ab 6:12")
        progress.record("v", position: 1460, duration: 1532) // 95.3 %
        XCTAssertEqual(progress.label("v"), "Gesehen")
        // Kept across instances (a relaunch).
        XCTAssertEqual(PlaybackProgress(defaults: defaults).label("v"), "Gesehen")
    }
}
