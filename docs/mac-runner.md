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
on `ubuntu-latest` and hands `runs-on` to "Build and test". Its tests,
`scripts/mac-runner/test-pick-runner.sh`, run in the same job first.

| Event | Runner |
|---|---|
| push to `main`, hand run | the Mac, if online and idle |
| pull request from a branch of this repository | the Mac, if online and idle |
| pull request from a fork | GitHub, always |
| the weekly scheduled run | GitHub, always: it checks the hosted image the TestFlight job needs |
| repository variable `MAC_RUNNER` = `off` | GitHub, always |
| Mac offline, not registered, or the status token missing or expired | GitHub |
| Mac busy | wait up to 20 minutes for it, then GitHub |

**The fallback asks GitHub before it queues.** A job sent to a self-hosted label waits up to 24
hours for that runner and cannot be moved once queued, so the pick job reads the runner's state
(`online`, `busy`) from the API first. That API needs the repository's Administration
permission, which `GITHUB_TOKEN` never has; the secret `MAC_RUNNER_STATUS_TOKEN` holds a
fine-grained token with only "Administration: read" on this one repository. Without the secret,
everything runs on GitHub as before. The summary of every run names the runner and why.

One gap: two runs that ask in the same second both see an idle Mac, and the second waits on the
Mac for the first to finish (about one run's length) instead of going to GitHub.

The TestFlight job stays on GitHub. No Apple secret ever reaches the Mac.

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
creates the user, the wall and the three LaunchDaemons:

| LaunchDaemon | Runs | What |
|---|---|---|
| `de.iphoneblog.ci-runner` | always, as `ci` | the Actions runner, `/Users/ci/actions-runner`, label `mac-studio`, log `/Users/ci/Library/Logs/actions-runner.log` |
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
- **Restart the runner:** `sudo launchctl kickstart -k system/de.iphoneblog.ci-runner`
- **Ports:** the Mac is shared with Thorsten's own test runs, which hold 8008 (test
  homeserver) and 8793 (blog fixture). Jobs here use 18008 and 18793
  (`TEST_HOMESERVER_PORT`, `FIXTURE_PORT`).
- **Swift package cache:** one per kind of runner (`spm-self-hosted-…`, `spm-github-hosted-…`),
  because the packages record absolute paths and the workspaces differ.
- **Disk:** a job needs about 40 GB free (iOS runtime, derived data, Swift packages,
  simulators). The checkout wipes `build/` at the start of every job.

## Removal

```bash
scripts/mac-runner/remove.sh
```

unregisters the runner, stops and deletes the three LaunchDaemons and the network wall, and ends
whatever still runs as `ci`. CI carries on at once on GitHub's runner. `--delete-user` deletes
the user `ci` and its home as well. The home folders stay closed; the script prints the modes
they had. Developer mode (`DevToolsSecurity`) stays on.
