# Performance

The app must scroll smoothly at 60 Hz. Thorsten decided on 2026-11-18 that 60 Hz is enough:
there is no 120 Hz requirement, no 120 Hz gate and no device runner. CI runs a smoke test only
("The gate" below). MetricKit's numbers from testers are information, not a gate. The budget is
in the WordPress repository, `docs/chat.md`, "Performance"; this page says how the numbers are
measured, where they come from, and how to read them.

## 120 Hz is allowed, not required

**`CADisableMinimumFrameDurationOnPhone` in Info.plist** (`project.yml`). Without it iOS caps
every iPhone app at 60 Hz, whatever its views ask for; an iPad needs no key. UIKit's scroll
views and SwiftUI's animations then run at up to 120 Hz on their own; nothing depends on it. The app has no
`CADisplayLink` of its own apart from the readout below.

**The readout.** A three-finger double tap anywhere shows a small box at the top right:
`max 120 · 119 fps · 9.1 ms`, the screen's maximum frame rate, the frames drawn in the last
second and the longest frame of that second. It works in every build, TestFlight included, and
a second double tap hides it. `max 60` on a Pro iPhone means the key is missing.
`App/Sources/Perf/FrameRateOverlay.swift`.

## Three sources of numbers

| | what | where |
|---|---|---|
| The simulator, in CI | hitch ratio while scrolling, open and switch times, launch | `scripts/perf.sh`, `.github/workflows/perf.yml` |
| A device on the Mac | Apple's own hitch ratio and frame rate | `scripts/perf.sh device`, "On a device" below |
| Testers' iPhones | MetricKit: hitch ratio, launch, hangs, frame rate | the `/rum` log lines, "From testers" below |

The simulator draws at 60 Hz on the Mac's GPU, so its numbers are not a phone's: #one-Chat and
the thread sit near 37 ms/s there whether or not the images are decoded off the main thread,
while the iPad drops from about 60 to 0. The simulator catches a change that makes a screen
slower than it was, on every pull request; the budget is checked on a device.

## The tests

`Tests/PerfTests/PerformanceTests.swift`, eight tests, five measured iterations each after one
warm-up:

| test | what | metrics |
|---|---|---|
| `testLaunch` | cold launch to the first frame that answers a touch, signed out | launch duration |
| `testOneChatAfterLaunch` | a launch with a stored session to the first #one messages, through a phone's 100 ms round trip | first messages (the app's own time) |
| `testScrollOneChat` | #one-Chat, 160 messages, 30 photos up to 4032x3024, flung up and down | hitch ratio, late frames |
| `testOpenThread` | channel to the long thread and back | clock time |
| `testScrollThread` | the long thread, 90 replies, 12 photos | hitch ratio, late frames |
| `testSwitchTabs` | Blog, #one-Chat, @Mentions, Ich, Blog | clock time |
| `testScrollBlog` | the Blog tab's web view on the blog fixture | hitch ratio, late frames |
| `testScrollSearch` | the search's list, 60 mixed hits with highlights from the fixture's search API | hitch ratio, late frames |

**The data.** `scripts/perf.sh` starts its own Synapse (a copy of `scripts/test-homeserver.sh`
on port 8048, `build/perf-synapse`), seeds it with `scripts/seed-perf-data.py`, and starts the
blog fixture on 8796, and `scripts/latency-proxy.py` on 8049 in front of the Synapse: 50 ms each
way, a phone on LTE. Against the local server every request answers at once, so start-up steps
that wait one after another show only through the proxy. Its own ports and its own simulator, always the same model (`PERF_MODEL`,
"iPhone 17 Pro", as `perf-iphone-17-pro`, whose keychain it resets each run): a missing model
fails the run rather than measure on another one. So it runs beside other test servers on a
shared Mac.

**The configuration.** `Perf`: Release's optimisation with the DEBUG condition on the app
target only, so the tests can point the app at the test server and sign in by themselves.
ChatKit and the packages build exactly as in Release.

**The hitch ratio in the simulator.** Xcode reports `XCTOSSignpostMetric`'s hitch numbers only
on a device. So the app, launched with `IPHONEBLOG_FPS=1`, counts its own frames: a frame is
late when it arrives more than half a frame after its slot, its hitch time is how late, and only
frames while a scroll view moves count, as in Apple's metric. It writes the totals to the file
`IPHONEBLOG_PERF_STATS` names, and `Tests/PerfTests/HitchMetric.swift` reads them before and
after each iteration. Through a file, not the accessibility tree: reading the tree makes XCUITest
snapshot the whole app on its main thread, the very thing being measured.

**The gate is a smoke test.** It catches a screen that got twice as slow, nothing finer.
`scripts/perf-gate.py` drops each metric's first iteration (the warm-up: caches, the first
layout) and takes the best of the other four, because a shared runner only ever adds time. It
fails when that best is more than twice its baseline in `scripts/perf-baseline.json`
(`tolerance.relative` 1.0) *and* over the absolute slack there. A test that did not run, a
metric it did not report, a log without numbers and a file without baselines fail too. The file
can hold hard budgets per test; it holds none, because the simulator's hitches are its own.

**Why no finer gate on CI.** The `xcode-27` runner is about four times slower than a Mac Studio
and far noisier. Measured on 2026-11-17 over ten runs of the same app, best after the warm-up:
the Blog's hitch ratio 4 to 34 ms/s from run to run (plain medians 15 to 90), the chat 137 to
289, the thread 116 to 268. The Mac Studio's simulator gives Blog 0 to 4.7, chat 40 to 49 and a
launch of 3.25 to 3.37 s. No threshold near a good run's number holds on that runner, and the
simulator draws at 60 Hz anyway.

**The baselines are CI's**: the median of the per-run bests of those ten runs, on the pinned
model. A failed test runs once more (`-retry-tests-on-failure`), because the loaded runner's
XCUITest now and then times out reading the screen. The simulator also hides WebKit's content
from XCUITest there, so the Blog test waits for the web view's scroll bar, not a word on the
page. Xcode's own baselines are tied to one machine's id and cannot follow GitHub's runners.
After a change that makes the app faster, write new baselines from that change's CI run, and
commit the file:

```bash
gh run download <run id> -n perf -D build/ci && cp build/ci/perf.log build/perf.log
python3 scripts/perf-gate.py build/perf.xcresult --write-baseline
```

On the Mac, the same tests, gated against CI's baselines (so they pass with room):

```bash
scripts/perf.sh               # build, run, gate
PERF_ONLY=testScrollOneChat scripts/perf.sh run
```

## On a device

```bash
APPLE_TEAM_ID=W9N692KH39 PERF_DEVICE_UDID=<udid> scripts/perf.sh device
```

The same tests, signed with the team (a device not yet in the team is registered on the first
build, which is the team holder's decision). The device reaches the test server and the fixture
over the Mac's LAN address: `scripts/lan-forward.py` listens there and forwards to the loopback,
under `/usr/bin/python3`, the Python the macOS firewall lets accept connections. The test taps
"Erlauben" on the local network prompt itself. Xcode reports Apple's hitch time ratio and frame
rate per test, for dragging and for the coast after a fling; the gate is not run, because a
device's numbers are not CI's. Read them against the budget in the WordPress `docs/chat.md`,
"Performance": a median under 5 ms/s per screen.

`xcrun devicectl list devices` finds the UDID. The device must be unlocked, with developer mode
on. The iPad Pro (12.9-inch, 5th generation) is registered; the app is universal, so it runs
there natively, not in iPhone compatibility mode.

## From testers

`App/Sources/Perf/MetricsReporter.swift`. iOS hands MetricKit's numbers to the app about once a
day, hangs as they happen. The app keeps a handful and sends them as the query string of one
POST to `https://<the Blog tab's host>/rum`, which `edge` answers with 204 itself; the log line
is the report (infra, `docs/monitoring.md`, the speed reports). Once per build it also sends the
screen's frame rate. These numbers are information for reading, not a gate.

**TestFlight only.** An App Store copy reports nothing (GDPR, Thorsten 2026-11-17). The same
binary moves from TestFlight to the App Store unchanged, so the app asks StoreKit's
AppTransaction where it came from: `.sandbox` (TestFlight) and `.xcode` report, `.production`
and anything unknown stay silent. `scripts/check-release-clean.sh`, run by the TestFlight lane,
fails a build whose binary lacks the gate's marker (`rum-gate-v1`); `MetricsGateTests` pins the
rule.

**What it sends, and nothing else:** `src=ios`, `kind` (`install`, `metrics`, `hang`), app version
and build, device model, iOS version, `hz` (the screen's maximum), `hitch` (ms/s), `launch_ms` and
`launch_opt_ms` (medians), `hang_n` and `hang_ms`. No message, room, user ID or call stack; the
request carries no cookie and no token. Never from a simulator or a test run. Like every request,
`edge` logs the address it came from.

**Reading it** in Grafana's Explore, Loki, tenant `alex`:

```logql
{host="edge"} | json | http_path="/rum" | http_query=~".*src=ios.*"
```

(infra `docs/monitoring/logs.md`, the speed reports.) `hz=120` on an iPhone model ending in
Pro proves the key; `hitch` under 5 is Apple's "good".

## What made it fast

**From launch to the first #one messages** (`testOneChatAfterLaunch`, the simulator through the
100 ms proxy, 2026-11-20, five launches each). The app times itself: from the moment the kernel
started the process to the first timeline with five items (`StartTrace`, `ChatOpenTrace`,
`FirstMessagesMetric`); a clock around `app.launch()` read 3.4 s on both sides, XCTest's own
launch and polling hiding the difference. Synapse was not the cause: its `/messages` p95 was
93 ms over the same day.

| | first messages |
|---|---|
| main (b3bcd84) | 3.08 s (2.91–3.52) |
| start-up waits in parallel | 2.68 s (2.59–2.94) |
| and 50 events per back-pagination | 2.57 s (2.44–2.70) |

| change | where |
|---|---|
| Bots, display name and picture load beside the screens; the app showed a spinner until all three round trips were done | `ChatSession.start()` |
| The three room aliases resolve at once, not one after another | `ChatSession.resolveRooms()` |
| The #one room list loads during start-up, once, not when the tab first appears | `ChatSession.loadOneRooms()` |
| 50 events per back-pagination, not 20: reactions, edits and state filled a page, and a room needed four round trips for its first screen | `TimelineViewModel` (patch) |

The log keeps every step with its time (subsystem `de.iphoneblog.chat`, categories `start` and
`open`), so a slow phone can be read with Console.


Measured on the iPad Pro on 2026-11-16, medians of five passes, hitch ratio while dragging /
while coasting:

| screen | before | after |
|---|---|---|
| #one-Chat | 57 / 0 ms/s, 90 / 108 fps | 0 / 3.5 ms/s, 97 / 115 fps |
| The long thread | 63 / 10.4 ms/s, 85 / 107 fps | 0 / 3.5 ms/s, 98 / 108 fps |
| Opening the thread, in and back | 5.4 s | 6.3 s |
| Blog tab | 0 / 0 ms/s | 0 / 0 ms/s |
| Launch | 0.35 s | 0.35 s |

| change | where |
|---|---|
| Timeline images decoded and scaled off the main thread, capped at 1024 px | `Vendor/ElementX/Shim/PreparedMediaProvider.swift` |

Single passes still spike to 190 to 210 ms/s while dragging, and the thread opens slower since a
photo row first shows its placeholder and lays out again when the decoded image arrives. Both
are open in the WordPress `docs/TODO.md`.

Hitches in the timeline, threads, @Mentions and the session code are the chat views' owners' to
fix; the list with causes went to them with these numbers.
