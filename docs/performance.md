# Performance

The app must scroll at 120 Hz on a ProMotion iPhone without hitches. The budget is in the
WordPress repository, `docs/chat.md`, "Performance"; this page says how the numbers are
measured, where they come from, and how to read them.

## 120 Hz is on

**`CADisableMinimumFrameDurationOnPhone` in Info.plist** (`project.yml`). Without it iOS caps
every iPhone app at 60 Hz, whatever its views ask for; an iPad needs no key. UIKit's scroll
views and SwiftUI's animations then run at up to 120 Hz on their own. The app has no
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

`Tests/PerfTests/PerformanceTests.swift`, six tests, five measured iterations each after one
warm-up:

| test | what | metrics |
|---|---|---|
| `testLaunch` | cold launch to the first frame that answers a touch, signed out | launch duration |
| `testScrollOneChat` | #one-Chat, 160 messages, 30 photos up to 4032x3024, flung up and down | hitch ratio, late frames |
| `testOpenThread` | channel to the long thread and back | clock time |
| `testScrollThread` | the long thread, 90 replies, 12 photos | hitch ratio, late frames |
| `testSwitchTabs` | Blog, #one-Chat, @Mentions, Ich, Blog | clock time |
| `testScrollBlog` | the Blog tab's web view on the blog fixture | hitch ratio, late frames |

**The data.** `scripts/perf.sh` starts its own Synapse (a copy of `scripts/test-homeserver.sh`
on port 8048, `build/perf-synapse`), seeds it with `scripts/seed-perf-data.py`, and starts the
blog fixture on 8796. Its own ports and simulator (`perf-iphone-pro`, whose keychain it resets
each run), so it runs beside other test servers on a shared Mac.

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

**The gate.** `scripts/perf-gate.py` takes each metric's median and fails when it is worse than
its baseline in `scripts/perf-baseline.json` by more than 50 % *and* the absolute slack there.
A test that did not run, a metric it did not report, a log without numbers and a file without
baselines fail too. The file can hold hard budgets per test; it holds none, because the
simulator's hitches are its own.

**The baselines are CI's.** The `xcode-27` runner is about four times slower than a Mac Studio
and noisier: a cold launch there takes 9 to 27 s, and one thread opening in five can take a
minute. So the baselines are medians of a CI run, written from the `perf` artifact's
`perf.log`. Five tests get their own slack (`per_test`): launch, gated on its clock time
because the runner's simulator does not always report Apple's launch metric, 10 s; opening the
thread, 7.6 s in one run and 12.1 s in the next with the same app, 8 s; the Blog's hitch ratio,
21 to 128 ms/s within one run, 40 ms/s; the chat's and the thread's hitch ratios, 92 to 245
ms/s from run to run, 150 ms/s. A failed test runs once more (`-retry-tests-on-failure`), because
the loaded runner's XCUITest now and then times out reading the screen. The gate on this runner catches a screen that gets
twice as slow; the device run is what measures fluidity. The simulator also hides WebKit's
content from XCUITest there, so the Blog test waits for the web view's scroll bar, not a word
on the page. Xcode's
own baselines are tied to one machine's id and cannot follow GitHub's runners. After a change
that makes the app faster, write new baselines from that change's CI run, and commit the file:

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
there natively at 120 Hz, not in iPhone compatibility mode.

## From testers

`App/Sources/Perf/MetricsReporter.swift`. iOS hands MetricKit's numbers to the app about once a
day, hangs as they happen. The app keeps a handful and sends them as the query string of one
POST to `https://<the Blog tab's host>/rum`, which `edge` answers with 204 itself; the log line
is the report (infra, `docs/monitoring.md`, the speed reports). Once per build it also sends the
screen's frame rate, which is how a TestFlight build proves 120 Hz on a Pro iPhone the day it is
installed.

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
