# The Mac Studio runner

"Build and test" runs on Thorsten's Mac Studio when it can, and on GitHub's hosted `xcode-27`
image otherwise. On GitHub the job took 66 to over 127 minutes in November 2026 and twice hit
the job limit; the Mac Studio is always on and nothing queues there. Thorsten decided this on
2026-11-20, as a named exception to the rule that nothing runs on his Mac (infra repository,
`docs/architecture.md`, "Nothing runs on Thorsten's Mac").

The Mac holds his keychain with the age key for the infra secrets, the ssh keys to `iron` and
his mail. A job must reach none of it, so isolation is the point of everything below.

## Which runner

The job "Pick a runner" in `.github/workflows/build.yml` runs `scripts/mac-runner/pick-runner.sh`
on `ubuntu-latest` and hands `runs-on` to "Build" and the four "Tests" shards: a run stays on one
kind of runner. Its tests, `scripts/mac-runner/test-pick-runner.sh`, run in the same job first.
"Idle" means no online instance of the four is busy.

| Event | Runner |
|---|---|
| push to `main`, hand run | the Mac, if online and idle |
| pull request from a branch of this repository | the Mac, if online and idle |
| pull request from a fork | GitHub, always |
| the weekly scheduled run | GitHub, always: it checks the hosted image the TestFlight job needs |
| repository variable `MAC_RUNNER` = `off` | GitHub, always |
| Mac offline, not registered, or the status token missing or expired | GitHub |
| Mac busy | wait up to 20 minutes for it (repository variable `MAC_RUNNER_WAIT`), then GitHub |

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

On the Mac the four shards run side by side on four runner instances (`mac-studio`,
`mac-studio-2` … `-4`, LaunchDaemons `de.iphoneblog.ci-runner`, `-2` … `-4`). Each instance's
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

`.github/workflows/mac-runner-check.yml` proves the wall from inside a job, weekly and on every
pull request that changes `scripts/mac-runner/`: it runs as `ci`, has no admin, sudo or keychain,
cannot list another home, cannot reach `iron`, the router or the NAS (all open to Thorsten's
user), and does reach the internet and loopback. By hand: `sudo -u ci -H scripts/mac-runner/check-isolation.sh`.

Branches of this repository are trusted: whoever can push here can already change the app.

External disks mounted with "Ignore ownership on this volume" are open to every user; `setup.sh`
names each and the command that closes it (`sudo diskutil enableOwnership <volume>`).

## Setup

Once, as Thorsten, in a checkout of this repository:

```bash
scripts/mac-runner/setup.sh
```

It fetches a registration token with his `gh` login, asks for the Mac password once, and then
creates the user, the wall and the LaunchDaemons. Run it while no job runs: a changed service
definition restarts its runner.

| LaunchDaemon | Runs | What |
|---|---|---|
| `de.iphoneblog.ci-runner`, `-2` … `-4` | always, as `ci` | the four runner instances, `/Users/ci/actions-runner`, `-2` … `-4`, label `mac-studio`, logs `/Users/ci/Library/Logs/<label>.log` |
| `de.iphoneblog.ci-runner.pf` | at boot, every 5 minutes, as root | loads the network wall if it is missing |
| `de.iphoneblog.ci-runner.xcode` | at boot, daily 05:10, after an Xcode update, as root | Xcode licence, first launch, iOS runtime; holds the runner back until they are ready (below) |

Then the status token, in the browser: GitHub → Settings → Developer settings → Fine-grained
tokens → Generate new token. Resource owner `Philipp-solutions-de`, only the repository
`iphoneblog-matrix-ios`, permission Administration: Read-only, expiry one year. Store it without
printing it:

```bash
gh secret set MAC_RUNNER_STATUS_TOKEN -R Philipp-solutions-de/iphoneblog-matrix-ios
```

`setup.sh` changes nothing on a second run, so it is also the repair: run it again.

## Xcode

The workflow wants Xcode `XCODE_MAJOR` (27). GitHub's image picks its newest 27.x, betas
included; the Mac uses `/Applications/Xcode.app`. "Check Xcode and the iOS runtime" fails the
job when the Mac has another major version, or no simulator runtime for its SDK.

- **Xcode itself** updates through the App Store with automatic updates on, signed in with
  Thorsten's Apple ID. That sign-in is the one thing only he can do. A new major Xcode (28) means
  changing `XCODE_MAJOR` in the same pull request that moves the hosted image.
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
- **Restart a runner:** `sudo launchctl kickstart -k system/de.iphoneblog.ci-runner` (`-2` … `-4`
  for the others)
- **Ports:** each instance's own (Test shards, above); `TEST_HOMESERVER_PORT` and
  `FIXTURE_PORT` default to 8008 and 8793 everywhere else.
- **Swift package cache:** one per kind of runner (`spm-self-hosted-…`, `spm-github-hosted-…`),
  because the packages record absolute paths and the workspaces differ.
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
scripts/mac-runner/remove.sh
```

unregisters the four runners, stops and deletes the LaunchDaemons and the network wall, and ends
whatever still runs as `ci`. CI carries on at once on GitHub's runner. `--delete-user` deletes
the user `ci` and its home as well. The home folders stay closed; the script prints the modes
they had. Developer mode (`DevToolsSecurity`) stays on.
