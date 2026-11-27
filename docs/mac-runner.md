# The Mac runners

"Build and test" runs on one of Thorsten's two Macs when it can, and on GitHub's hosted
`xcode-27` image otherwise: first his MacBook Pro (label `mbp`, M1 Pro, 16 GB), then his Mac
Studio (label `mac-studio`, M2 Max, 32 GB). On GitHub the job took 66 to over 127 minutes in
November 2026 and twice hit the job limit; on a Mac nothing queues. Thorsten decided the Mac
Studio on 2026-11-20 and the MacBook Pro as the default on 2026-11-25, as named exceptions to
the rule that nothing runs on his Mac (infra repository, `docs/runners.md`, "The Mac runners").

Both Macs hold his keychain with the age key for the infra secrets, the ssh keys to `iron` and
his mail. A job must reach none of it, so isolation is the point of everything below.

## Which runner

The job "Pick a runner" in `.github/workflows/build.yml` runs `scripts/mac-runner/pick-runner.sh`
on `ubuntu-latest` (the repository is public: free minutes, and `iron` takes private repositories only) and hands `runs-on` to "Build" and the four "Tests" shards: a run stays on one kind of
runner. Its tests, `scripts/mac-runner/test-pick-runner.sh`, run in the same job first.

**The MacBook Pro is the default, the Mac Studio only a fallback** (Thorsten, 2026-11-25). The
Studio is the machine he works on; four simulators there at once put its load above 800.

| Event | Runner |
|---|---|
| push to `main`, hand run, pull request from a branch of this repository | the MacBook Pro while it is online, busy or not: the run waits there for a free instance |
| the same, MacBook Pro offline | wait up to 30 minutes (repository variable `MAC_FALLBACK_MINUTES`) for it to come back; then the Mac Studio if online and idle, else GitHub |
| the same, MacBook Pro not registered | the Mac Studio at once if online and idle, else GitHub |
| pull request from a fork | GitHub, always |
| the weekly scheduled run | GitHub, always: it checks the hosted image the TestFlight job needs |
| repository variable `MAC_RUNNER` = `off` | GitHub, always |
| the status token missing or expired | GitHub |

Each Mac's priority is set by `setup.sh --priority` (Priority, below); the repository variable
`MAC_RUNNER_PRIORITY` no longer changes it on either Mac.

The order lives in `pick-runner.sh` (`MAC_MACHINES`, default `mbp mac-studio`: the first is the default, the rest are fallbacks). A run stays on
the Mac it was given: its build hands the products to its test shards on that Mac's disk.

**The fallback asks GitHub before it queues.** A job sent to a self-hosted label waits up to 24
hours for that runner and cannot be moved once queued, so the pick job reads the runner's state
(`online`, `busy`) from the API first. That API needs the repository's Administration
permission, which `GITHUB_TOKEN` never has; the secret `MAC_RUNNER_STATUS_TOKEN` holds a
fine-grained token with only "Administration: read" on this one repository. Without the secret,
everything runs on GitHub as before. The summary of every run names the runner and why.

One gap: two runs that ask in the same second both see an idle Mac, and the second waits on the
Mac for the first to finish (about one run's length) instead of going to GitHub.

The TestFlight job stays on GitHub. No Apple secret ever reaches the Mac.

## Test shards

"Build" runs `scripts/build.sh build-for-testing` once: the app and the unit, sign-in and UI test
bundles. Four jobs "Tests (n/4)" then test those products without building
(`TEST_WITHOUT_BUILDING=1`), each against its own test homeserver. Shard 1 also runs the unit and
sign-in tests.

`scripts/ui-shards.py` splits the UI tests: it takes every test the built products hold
(`build.sh enumerate-ui`), gives each its time from `scripts/ui-test-times.json` (seconds per
test, measured on the Mac Studio; a new test counts as the median), and deals them out longest
first to the shard with the least time. Every shard computes the same split, and the script
fails unless the four together hold every test exactly once. Refresh the times file from a green
run's `ui.log` when the split drifts.

**How many jobs at once** (Thorsten, 2026-11-25): two on the MacBook Pro (`mbp`, `mbp-2`), one
on the Mac Studio (`mac-studio`); LaunchDaemons `de.iphoneblog.ci-runner` and `-2`. Four
simulators at once put the Studio's load at 430 to 880 that evening. So a run's four shards go
two at a time on the MacBook Pro and one after the other on the Studio.

**One build at a time on a Mac.** Two runs on one Mac share the user `ci` and with it one Xcode
build service; when two `build-for-testing` ran at once on the MacBook Pro on 2026-11-25, one
waited 42 minutes for a service that no longer answered it. `scripts/mac-runner/one-build.sh`
makes the second wait for the first. Shards do not build and need no lock.

Each instance's
`.env` gives it its own ports (`180n8` for the homeserver, `180n9` for the blog fixture) and its
own simulator (`iPhone 17 Pro (CI n)`), so shards never meet each other or Thorsten's own test
runs on 8008 and 8793. The products pass from "Build" to the shards on the Mac's disk
(`~ci/ci-products/<run>`, cleared after a day); on GitHub every shard is another machine, so
they travel as a one-day artifact, in a tar because an artifact drops the executable bits.

## TestFlight

On `main` the upload starts as soon as "Build" is green and does not wait for the tests. A red
test then shows on that run and holds back the next upload: "Pick a runner" asks
`scripts/ci-last-main-tests.sh` whether the last finished `main` build had red tests, and if so
this run's upload is the job "TestFlight (after the tests …)", which waits for its own tests. A
fix therefore still reaches TestFlight once its tests pass. Pull requests need all four shards
green to merge.

## Priority

Every job on a Mac runs at low CPU priority, so Thorsten's own work never stutters (his rule,
2026-11-21). How low is `setup.sh --priority`:

| Mac | `--priority` | What |
|---|---|---|
| Mac Studio | `background` | `ProcessType` Background, `Nice` 20, low-priority I/O, and the background QoS class (`taskpolicy -b`): efficiency cores only, yields the disk |
| MacBook Pro | `nice` | `ProcessType` Standard, `Nice` 20, low-priority I/O: every core, but anything of Thorsten's comes first. Its M1 Pro has two efficiency cores, too few for a build (Thorsten, 2026-11-25) |

Every process the runner service starts inherits that. Besides, the job's first step starts
`scripts/mac-runner/lower-priority.sh`, which every 5 seconds gives each process of the user
`ci` nice 20 and, on `background`, the background QoS class (`MAC_PRIORITY` in the runner's
`.env` says which). A loop over the user rather than a wrapper around the job, because the simulators,
`XCBBuildService`, `SWBBuildService` and the compilers they start come from launchd and XPC,
outside the job's process tree. The runner ends the loop with the job, and each test shard shuts down its own simulator at
the end (`scripts/mac-runner/shutdown-simulator.sh`), so none idles between jobs. The step "The job's
processes and their priority" lists them with nice and priority at the end of each job. Changing a Mac's
priority means `setup.sh` with the other `--priority`.

## Isolation

`scripts/mac-runner/setup.sh` builds all of this; each part answers one way in.

| Part | What it keeps out |
|---|---|
| user `ci`: standard, hidden, own group, no password, no login, no keychain secrets | the runner never runs as Thorsten |
| every other home folder `chmod 700` | macOS makes homes 755, so any user could read `~/localprojects`, `~/worktrees`, `SynologyDrive` |
| pf anchor `com.apple/ci-runner`, reloaded every five minutes by `de.iphoneblog.ci-runner.pf` | `ci` reaches loopback and the internet only: not `iron` over WireGuard, not the LAN, NAS or Home Assistant |
| forks never routed to the Mac (above) | strangers' code |
| repository setting: approval required for **all** outside contributors | a fork that edits `build.yml` to name the Mac anyway |

**The routing alone does not stop a hostile fork.** A pull request runs the workflow file of its
own merge commit, so a fork can rewrite `runs-on`. What stops it is the approval: no workflow of
an outside contributor runs until someone with write access presses "Approve and run". **Read the
diff of `.github/` before you approve.** The setting is under Settings → Actions → General →
"Approval for running fork pull request workflows from contributors", set to "Require approval
for all external contributors" on 2026-11-20. Check it:

```bash
gh api repos/Philipp-solutions-de/iphoneblog-matrix-ios/actions/permissions/fork-pr-contributor-approval
```

`.github/workflows/mac-runner-check.yml` proves the wall from inside a job on each Mac that is
online, weekly and on every pull request that changes `scripts/mac-runner/`: it runs as `ci`, has no admin, sudo or keychain,
cannot list another home, cannot reach `iron`, the router or the NAS (all open to Thorsten's
user), and does reach the internet and loopback. By hand: `sudo -u ci -H scripts/mac-runner/check-isolation.sh`.

Branches of this repository are trusted: whoever can push here can already change the app.

External disks mounted with "Ignore ownership on this volume" are open to every user; `setup.sh`
names each and the command that closes it (`sudo diskutil enableOwnership <volume>`).

## Setup

Once per Mac, as Thorsten, in a checkout of this repository:

```bash
scripts/mac-runner/setup.sh --count 1                                   # the Mac Studio
scripts/mac-runner/setup.sh --machine mbp --count 2 --priority nice     # the MacBook Pro
```

`--machine` is the runner label and the instances' names, `--count` the number of instances
(more are stopped and unregistered), `--priority` as in Priority, above. It fetches a registration token with his `gh` login, asks for the Mac password once, and then
creates the user, the wall and the LaunchDaemons. Run it while no job runs: a changed service
definition restarts its runner.

| LaunchDaemon | Runs | What |
|---|---|---|
| `de.iphoneblog.ci-runner` (and `-2` on the MacBook Pro) | always (a laptop: on power), as `ci` | the runner instances, `/Users/ci/actions-runner` (and `-2`), label `mac-studio` or `mbp`, logs `/Users/ci/Library/Logs/<label>.log` |
| `de.iphoneblog.ci-runner.pf` | at boot, every 5 minutes, as root | loads the network wall if it is missing |
| `de.iphoneblog.ci-runner.xcode` | at boot, daily 05:10, after an Xcode update, as root | Xcode licence, first launch, iOS runtime; holds the runner back until they are ready (below) |
| `de.iphoneblog.ci-runner.power` | a Mac with a battery only: at boot, every 30 seconds, as root | starts the runners on power, stops them on battery or hold (On a laptop, below) |
| `de.iphoneblog.ci-runner.awake` | a Mac with a battery only: always, as root | `caffeinate -s`: no system sleep while on power |

Then the status token, in the browser: GitHub → Settings → Developer settings → Fine-grained
tokens → Generate new token. Resource owner `Philipp-solutions-de`, only the repository
`iphoneblog-matrix-ios`, permission Administration: Read-only, expiry one year. Store it without
printing it:

```bash
gh secret set MAC_RUNNER_STATUS_TOKEN -R Philipp-solutions-de/iphoneblog-matrix-ios
```

`setup.sh` changes nothing on a second run, so it is also the repair: run it again.

The MacBook Pro has no `gh` login. Its runners were registered from the Mac Studio: a
registration token from `gh api -X POST repos/…/actions/runners/registration-token` in a file
copied to the MacBook Pro, then `sudo scripts/mac-runner/setup.sh --as-root <file> --machine mbp
--count 2 --priority nice` there (a removal token, when instances go, in `<file>.remove`), and the file deleted.

## On a laptop

The MacBook Pro takes jobs only while its **CPU gate** is open: at home, on power, and Thorsten
idle for 10 minutes or the screen locked (Thorsten, 2026-11-27). A root daemon on the MBP keeps
the gate (infra repository, `mac/cpu-gate/`, `docs/runners.md` "The CPU gate"), writes
`/Users/Shared/cpu-gate/state` and calls `power-switch.sh` within about 2 seconds of a change.
`power-switch.sh` also checks every 30 seconds by itself:

- **Gate closed**: it stops every runner at once, a job in the middle included, then ends every
  process of `ci` (the job, its simulators, its build service). The run fails or is cancelled;
  Thorsten accepts that. Jobs queued on the Mac's label wait until the gate opens again, or until
  GitHub drops them after a day.
- **On power**, gate open (or no gate, as on the Mac Studio), and Xcode ready: it starts every
  runner. `caffeinate -s` keeps the Mac awake
  while it is plugged in; the display may sleep. A closed lid without an external display still
  sleeps, and the runners then show offline.
- **On battery** without a gate: it stops each instance without a job at once, so none takes a new one, and
  lets the instances with a job finish it. Jobs already queued on the Mac's label (a run's test
  shards after its build) go to those, one after the other, instead of waiting there for a day.
  Once no job has run for two checks in a row, the last instances stop too.
- **Hold**: while `/Users/Shared/ci-runner-hold` exists, it acts as on battery. Any user may
  create the file, for example before a game test on the same Mac (trebuchet-testlab), and
  delete it afterwards. `pgrep -f Runner.Worker` printing nothing means no job runs.

pick-runner.sh then sees the MacBook Pro offline and sends the next run to the Mac Studio. The
power switch also stops and starts a runner a user installed with the runner's own `svc.sh`
(LaunchAgents `actions.runner.*`). Log: `/var/log/ci-runner-power.log`.

## Xcode

The workflow wants Xcode `XCODE_MAJOR` (27). GitHub's image picks its newest 27.x, betas
included; the Mac uses `/Applications/Xcode.app`. "Check Xcode and the iOS runtime" fails the
job when the Mac has another major version, or no simulator runtime for its SDK.

- **Xcode itself**, on the Mac Studio, updates through the App Store with automatic updates on,
  signed in with Thorsten's Apple ID. That sign-in is the one thing only he can do. A new major
  Xcode (28) means changing `XCODE_MAJOR` in the same pull request that moves the hosted image.
- **The MacBook Pro gets a copy** of the Mac Studio's Xcode and iOS runtime:
  `scripts/mac-runner/copy-xcode.sh mbp`, run on the Mac Studio. There the App Store asks for
  his password on every install, and `xcodebuild -downloadPlatform iOS` fails as root. The
  script needs passwordless sudo on the MacBook Pro while it runs. Run it after the Mac Studio's
  Xcode updates; a MacBook Pro with an older 27.x keeps working, one with another major fails
  its jobs at "Xcode".
- **Everything after an update** is `de.iphoneblog.ci-runner.xcode`. It starts when Xcode's
  `version.plist` changes, at boot and daily at 05:10. It accepts the licence, runs the
  first-launch install, and downloads the iOS simulator runtime that matches the new SDK
  (`xcodebuild -downloadPlatform iOS`, 8.3 GB, no Apple ID needed, about an hour). **While
  Xcode is not ready it stops the runner**, so GitHub sees the Mac offline and every job goes
  to GitHub's runner instead of failing; it starts the runner again when the runtime is in.
  Log: `/var/log/ci-runner-xcode.log`. To run it now:
  `sudo launchctl kickstart -k system/de.iphoneblog.ci-runner.xcode`.
- **The runner** updates itself to each new release.

## Running it

- **State:** `gh api repos/Philipp-solutions-de/iphoneblog-matrix-ios/actions/runners --jq '.runners[] | {name,status,busy}'`
- **Send everything to GitHub for a while:** `gh variable set MAC_RUNNER -b off -R Philipp-solutions-de/iphoneblog-matrix-ios`;
  `gh variable delete MAC_RUNNER …` brings the Mac back.
- **Restart a runner:** `sudo launchctl kickstart -k system/de.iphoneblog.ci-runner` (`-2` for the
  second instance on the MacBook Pro)
- **Keep jobs off the MacBook Pro for a while:** `touch /Users/Shared/ci-runner-hold` there,
  `rm` it to take jobs again (On a laptop, above).
- **Ports:** each instance's own (Test shards, above); `TEST_HOMESERVER_PORT` and
  `FIXTURE_PORT` default to 8008 and 8793 everywhere else.
- **Swift package cache:** one per workspace folder (`spm-github-hosted-github-…` on GitHub,
  `spm-self-hosted-<runner name>-…` on the Macs), because the packages record absolute paths
  and every runner instance has its own folder.
- **Disk:** a job needs about 40 GB free (iOS runtime, derived data, Swift packages,
  simulators). The checkout wipes `build/` at the start of every job.

## Measured

PR #53, 2026-11-20, the same code on both runners:

| Step | GitHub `xcode-27` | Mac Studio |
|---|---:|---:|
| waiting for a runner | 60 min (53 on a second run) | 0 |
| build | 5.3 | 1.1 |
| unit tests | 9.2 | 2.5 |
| sign-in test | 5.7 | 2.5 |
| UI tests | 84.2 | 80.2 |
| the job | 108 | 88 |
| push to result | 168 | 89 |

Building and unit testing are four times as fast; the UI tests are not, so the gain is the
queue and the first 20 minutes. RichMessagesUITests alone takes 22.5 minutes on the Mac. The
runner has no window session (a LaunchDaemon), so the simulator may render without the GPU;
splitting the UI tests into parallel simulators is the next lever (architecture.md, "Open
points", CI time).

**The simulator is an iPhone 17 Pro, chosen by name.** The iOS 27.2 runtime's default devices
hold only the iPhone Duo, a foldable whose inner screen gets the iPad layout without a tab bar;
53 UI test runs failed on it before `scripts/build.sh` stopped taking the first iPhone listed.
It creates the iPhone 17 Pro when the machine has none (`DEVICE_TYPE` picks another).

## Removal

```bash
scripts/mac-runner/remove.sh                    # the Mac Studio
scripts/mac-runner/remove.sh --machine mbp      # the MacBook Pro
```

unregisters that Mac's runners, stops and deletes the LaunchDaemons and the network wall, and ends
whatever still runs as `ci`. CI carries on at once on GitHub's runner. `--delete-user` deletes
the user `ci` and its home as well. The home folders stay closed; the script prints the modes
they had. Developer mode (`DevToolsSecurity`) stays on.
