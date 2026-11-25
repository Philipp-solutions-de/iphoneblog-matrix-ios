#!/usr/bin/env bash
# Set up the self-hosted GitHub Actions runner on one of the Macs (docs/mac-runner.md).
#
#   scripts/mac-runner/setup.sh                              # the Mac Studio: mac-studio, 4 instances
#   scripts/mac-runner/setup.sh --machine mbp --count 4      # the MacBook Pro
#
# --machine is the runner label and the instances' names (<machine>, <machine>-2 …), which
# pick-runner.sh asks for; --count is how many instances, one per job that may run at once
# (instances above it are stopped and unregistered); --priority is `background` (nice 20 and
# the background QoS class: efficiency cores only, the Mac Studio) or `nice` (nice 20 on every
# core: the MacBook Pro, whose M1 Pro has only two efficiency cores).
#
# Run it as the Mac's admin user, not with sudo: it fetches the registration token with your
# `gh` login, then asks for your password once (sudo) for the rest. Every step checks first, so
# a second run changes nothing and a broken first run can simply be repeated.
#
# What it does:
#   1. creates the hidden standard user `ci` with its own group, no password and no login
#   2. puts `ci` in _developer, so xcodebuild may attach to the simulator without a prompt
#   3. closes every other home folder to other users (chmod go-rwx)
#   4. keeps `ci` off private networks with a pf anchor (iron's WireGuard, the LAN, the NAS)
#   5. a daily root job that keeps Xcode's licence, first launch and iOS runtime in step
#   6. downloads the Actions runner (checksum checked), registers the instances for this one
#      repository with the machine's label, and starts each as a LaunchDaemon under `ci`
#   7. on a Mac with a battery: the power switch (jobs only on power) and no sleep on power
set -euo pipefail

repo="Philipp-solutions-de/iphoneblog-matrix-ios"
user="ci"
# Four instances by default, so the four test shards of a run go side by side
# (docs/mac-runner.md, "Test shards").
machine="mac-studio"
runner_count=4
priority=background
as_root=no
token_file=""
while (( $# )); do
    case "$1" in
    --machine) machine="$2"; shift 2 ;;
    --count) runner_count="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --as-root) as_root=yes; token_file="$2"; shift 2 ;;
    *) echo "usage: $0 [--machine <label>] [--count <n>] [--priority background|nice]" >&2; exit 1 ;;
    esac
done
[[ "$machine" =~ ^[a-z][a-z0-9-]*$ && "$runner_count" =~ ^[1-9]$ && "$priority" =~ ^(background|nice)$ ]] ||
    { echo "--machine wants a lowercase label, --count 1 to 9, --priority background or nice." >&2; exit 1; }
if [[ "$priority" == background ]]; then process_type=Background; else process_type=Standard; fi
labels="$machine"
slot_name()  { if [[ "$1" == 1 ]]; then echo "$machine"; else echo "$machine-$1"; fi; }
slot_dir()   { if [[ "$1" == 1 ]]; then echo "/Users/$user/actions-runner"; else echo "/Users/$user/actions-runner-$1"; fi; }
slot_label() { if [[ "$1" == 1 ]]; then echo de.iphoneblog.ci-runner; else echo "de.iphoneblog.ci-runner-$1"; fi; }
runner_version="2.338.2"
runner_sha256="25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388"
support="/Library/Application Support/ci-runner"
here="$(cd "$(dirname "$0")" && pwd)"

if [[ "$as_root" != yes ]]; then
    [[ "$(id -u)" != 0 ]] || { echo "Run this as yourself, not with sudo." >&2; exit 1; }
    [[ "$(uname -m)" == arm64 ]] || { echo "This is for an Apple-silicon Mac." >&2; exit 1; }
    [[ -d /Applications/Xcode.app ]] || { echo "No /Applications/Xcode.app." >&2; exit 1; }
    free_gib=$(( $(df -k /System/Volumes/Data | awk 'NR==2 {print $4}') / 1024 / 1024 ))
    if (( free_gib < 40 )); then
        echo "Only ${free_gib} GiB free on the data volume; the runner needs about 40 (iOS runtime," >&2
        echo "derived data, Swift packages, simulators). Free some space first." >&2
        exit 1
    fi
    token_file="$(mktemp)"
    chmod 600 "$token_file"
    trap 'rm -f "$token_file"' EXIT
    missing=no surplus=no
    for slot in $(seq 1 "$runner_count"); do [[ -f "$(slot_dir "$slot")/.runner" ]] || missing=yes; done
    for slot in $(seq $((runner_count + 1)) 9); do [[ ! -f "/Library/LaunchDaemons/$(slot_label "$slot").plist" ]] || surplus=yes; done
    # Prints nothing: each token goes straight into a file only root and you can read.
    if [[ "$missing" == yes ]]; then
        gh api -X POST "repos/$repo/actions/runners/registration-token" --jq .token > "$token_file"
        [[ -s "$token_file" ]] || { echo "No registration token (gh login with admin on $repo?)." >&2; exit 1; }
    fi
    if [[ "$surplus" == yes ]]; then
        gh api -X POST "repos/$repo/actions/runners/remove-token" --jq .token > "$token_file.remove"
        chmod 600 "$token_file.remove"
        trap 'rm -f "$token_file" "$token_file.remove"' EXIT
    fi
    echo "Now sudo asks for your Mac password."
    sudo "$0" --as-root "$token_file" --machine "$machine" --count "$runner_count" --priority "$priority"
    exit 0
fi

step() { printf '\n== %s\n' "$*"; }

# 1. The user. dscl rather than sysadminctl, because sysadminctl wants a password and this
# account must have none: nobody signs in as `ci`, launchd starts its one process.
step "user $user"
if ! dscl . -read "/Users/$user" UniqueID >/dev/null 2>&1; then
    id_=600
    while dscl . -search /Users UniqueID "$id_" | grep -q . ||
          dscl . -search /Groups PrimaryGroupID "$id_" | grep -q .; do id_=$((id_ + 1)); done
    dscl . -create "/Groups/$user"
    dscl . -create "/Groups/$user" PrimaryGroupID "$id_"
    dscl . -create "/Groups/$user" RealName "CI runner"
    dscl . -create "/Users/$user"
    dscl . -create "/Users/$user" UniqueID "$id_"
    dscl . -create "/Users/$user" PrimaryGroupID "$id_"
    dscl . -create "/Users/$user" RealName "CI runner"
    dscl . -create "/Users/$user" UserShell /bin/zsh
    dscl . -create "/Users/$user" NFSHomeDirectory "/Users/$user"
    dscl . -create "/Users/$user" Password '*'
    dscl . -create "/Users/$user" IsHidden 1
    echo "created $user with uid and gid $id_"
else
    echo "exists"
fi
uid="$(id -u "$user")"
# A laptop starts its runners only through the power switch (on power, no hold, Xcode ready),
# also right after this script changed them (docs/mac-runner.md, "On a laptop").
start_runner=start
if pmset -g batt | grep -q InternalBattery; then start_runner=nostart; fi
gid="$(id -g "$user")"
if dseditgroup -o checkmember -m "$user" admin >/dev/null 2>&1; then
    echo "$user is an admin; refusing. Remove it from the admin group first." >&2
    exit 1
fi
mkdir -p "/Users/$user"
chown "$user:$gid" "/Users/$user"
chmod 700 "/Users/$user"

# 2. Developer tools without an authorisation prompt (no one is there to answer it).
step "developer tools"
dseditgroup -o checkmember -m "$user" _developer >/dev/null 2>&1 ||
    dseditgroup -o edit -a "$user" -t user _developer
DevToolsSecurity -status | grep -q enabled || DevToolsSecurity -enable

# 3. Other homes. macOS creates them 755, so any user can read localprojects, worktrees and
# SynologyDrive. Record the old mode once, for docs/mac-runner.md "Removal".
step "home folders closed to other users"
mkdir -p "$support"
for home in /Users/*; do
    name="$(basename "$home")"
    [[ -d "$home" && ! -L "$home" ]] || continue
    case "$name" in Shared|Guest|"$user"|.*) continue ;; esac
    dscl . -read "/Users/$name" UniqueID >/dev/null 2>&1 || continue
    mode="$(stat -f %Lp "$home")"
    grep -q "^$home " "$support/home-modes" 2>/dev/null || echo "$home $mode" >> "$support/home-modes"
    if [[ "$mode" != 700 ]]; then chmod go-rwx "$home"; echo "$home: $mode -> 700"; else echo "$home: 700"; fi
done
# External disks mounted with "ignore ownership" are readable and writable by every user.
mount | sed -nE 's/^.* on (\/Volumes\/.*) \(.*noowners.*$/\1/p' | while read -r mnt; do
    echo "WARNING: $mnt ignores ownership, so $user can read and write it." \
         "Fix: sudo diskutil enableOwnership \"$mnt\""
done

# 4. pf: the runner's user may reach loopback and the internet, nothing private.
step "network wall"
install -m 755 -o root -g wheel "$here/pf-apply.sh" "$support/pf-apply.sh"
sed "s/@UID@/$uid/g" "$here/ci-runner.pf" > "$support/ci-runner.pf"
chown root:wheel "$support/ci-runner.pf"
chmod 644 "$support/ci-runner.pf"
install_daemon() { # label, plist body[, nostart]: nostart leaves starting it to the power switch
    local plist="/Library/LaunchDaemons/$1.plist"
    local tmp; tmp="$(mktemp)"
    printf '%s\n' "$2" > "$tmp"
    plutil -lint "$tmp" >/dev/null
    if ! cmp -s "$tmp" "$plist" 2>/dev/null; then
        launchctl bootout "system/$1" 2>/dev/null || true
        # bootout returns before the service is gone; bootstrapping too soon fails with
        # "5: Input/output error" (2026-11-21, the runner after its priority change).
        for _ in $(seq 1 30); do launchctl print "system/$1" >/dev/null 2>&1 || break; sleep 1; done
        install -m 644 -o root -g wheel "$tmp" "$plist"
        if [[ "${3:-}" == nostart ]]; then
            echo "$1 written; the power switch starts it"
        else
            launchctl bootstrap system "$plist" || { sleep 5; launchctl bootstrap system "$plist"; }
            echo "$1 (re)loaded"
        fi
    else
        [[ "${3:-}" == nostart ]] || launchctl print "system/$1" >/dev/null 2>&1 || launchctl bootstrap system "$plist"
        echo "$1 unchanged"
    fi
    rm -f "$tmp"
}
install_daemon de.iphoneblog.ci-runner.pf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>de.iphoneblog.ci-runner.pf</string>
  <key>ProgramArguments</key><array><string>$support/pf-apply.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>300</integer>
  <key>StandardErrorPath</key><string>/var/log/ci-runner-pf.log</string>
</dict></plist>"
"$support/pf-apply.sh"

# 5. Xcode upkeep: licence, first launch, and the iOS runtime that matches the SDK.
step "Xcode upkeep"
install -m 755 -o root -g wheel "$here/xcode-upkeep.sh" "$support/xcode-upkeep.sh"
install_daemon de.iphoneblog.ci-runner.xcode "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>de.iphoneblog.ci-runner.xcode</string>
  <key>ProgramArguments</key><array><string>$support/xcode-upkeep.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>5</integer><key>Minute</key><integer>10</integer></dict>
  <key>WatchPaths</key><array><string>/Applications/Xcode.app/Contents/version.plist</string></array>
  <key>StandardOutPath</key><string>/var/log/ci-runner-xcode.log</string>
  <key>StandardErrorPath</key><string>/var/log/ci-runner-xcode.log</string>
</dict></plist>"

# 6. The runner.
step "runners"
# From /, because the caller sits in a home ci may not read (getcwd warnings otherwise).
as_ci() { (cd / && sudo -u "$user" -H "$@"); }
as_ci mkdir -p "/Users/$user/Library/Logs"
tarball="/Users/$user/actions-runner-$runner_version.tar.gz"
for slot in $(seq 1 "$runner_count"); do
    dir="$(slot_dir "$slot")"
    name="$(slot_name "$slot")"
    label="$(slot_label "$slot")"
    if [[ ! -x "$dir/config.sh" ]]; then
        if [[ ! -f "$tarball" ]]; then
            as_ci curl -fsSL -o "$tarball" \
                "https://github.com/actions/runner/releases/download/v$runner_version/actions-runner-osx-arm64-$runner_version.tar.gz"
            echo "$runner_sha256  $tarball" | shasum -a 256 -c -
        fi
        as_ci mkdir -p "$dir"
        as_ci tar -xzf "$tarball" -C "$dir"
    fi
    if [[ ! -f "$dir/.runner" ]]; then
        [[ -s "$token_file" ]] || { echo "No registration token." >&2; exit 1; }
        token="$(cat "$token_file")"
        (cd "$dir" && sudo -u "$user" -H ./config.sh --unattended --replace \
            --url "https://github.com/$repo" --token "$token" \
            --name "$name" --labels "$labels" --work _work)
        unset token
    else
        echo "$name: registered"
    fi
    # What a job finds: the system tools, Xcode's python3 and git, ~/.local/bin for uv. After
    # config.sh, which writes the caller's PATH into .path (it held Thorsten's own folders).
    # Each instance has its own ports and simulator, so four jobs side by side never meet, and
    # none meets Thorsten's own test runs on 8008 and 8793.
    as_ci sh -c "printf '%s\n' '/Users/$user/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin' > '$dir/.path'"
    as_ci sh -c "printf '%s\n' 'LANG=en_US.UTF-8' 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer' \
        'TEST_HOMESERVER_PORT=180${slot}8' 'FIXTURE_PORT=180${slot}9' 'DEVICE_NAME=iPhone 17 Pro (CI $slot)' \
        'MAC_PRIORITY=$priority' > '$dir/.env'"
    install_daemon "$label" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>$label</string>
  <key>UserName</key><string>$user</string>
  <key>GroupName</key><string>$user</string>
  <key>InitGroups</key><true/>
  <key>SessionCreate</key><true/>
  <key>ProgramArguments</key><array><string>$dir/bin/runsvc.sh</string></array>
  <key>WorkingDirectory</key><string>$dir</string>
  <key>EnvironmentVariables</key><dict>
    <key>HOME</key><string>/Users/$user</string>
    <key>USER</key><string>$user</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <!-- The lowest priority, inherited by every process the runner starts (xcodebuild, simctl,
       the test homeserver): Thorsten's work on this Mac comes first (docs/mac-runner.md,
       "Priority"). lower-priority.sh covers what launchd starts outside this tree. -->
  <key>ProcessType</key><string>$process_type</string>
  <key>Nice</key><integer>20</integer>
  <key>LowPriorityIO</key><true/>
  <key>LowPriorityBackgroundIO</key><true/>
  <key>StandardOutPath</key><string>/Users/$user/Library/Logs/$label.log</string>
  <key>StandardErrorPath</key><string>/Users/$user/Library/Logs/$label.log</string>
</dict></plist>" "$start_runner"
done
rm -f "$tarball"

# Instances above --count: stop, unregister, delete (their work folders go too).
for slot in $(seq $((runner_count + 1)) 9); do
    label="$(slot_label "$slot")"
    plist="/Library/LaunchDaemons/$label.plist"
    [[ -f "$plist" ]] || continue
    launchctl bootout "system/$label" 2>/dev/null || true
    for _ in $(seq 1 30); do launchctl print "system/$label" >/dev/null 2>&1 || break; sleep 1; done
    dir="$(slot_dir "$slot")"
    if [[ -f "$dir/.runner" && -s "$token_file.remove" ]]; then
        (cd "$dir" && sudo -u "$user" -H ./config.sh remove --token "$(cat "$token_file.remove")") || true
    fi
    rm -f "$plist"
    rm -rf "$dir"
    echo "$(slot_name "$slot") removed"
done

# 7. A laptop: jobs only on power, and on power it does not sleep (docs/mac-runner.md,
# "On a laptop"). caffeinate -s holds off system sleep only while on power; the display may
# still sleep, and a closed lid without an external display still sleeps.
if pmset -g batt | grep -q InternalBattery; then
    step "power switch"
    install -m 755 -o root -g wheel "$here/power-switch.sh" "$support/power-switch.sh"
    install_daemon de.iphoneblog.ci-runner.power "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>de.iphoneblog.ci-runner.power</string>
  <key>ProgramArguments</key><array><string>$support/power-switch.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>/var/log/ci-runner-power.log</string>
  <key>StandardErrorPath</key><string>/var/log/ci-runner-power.log</string>
</dict></plist>"
    install_daemon de.iphoneblog.ci-runner.awake "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>de.iphoneblog.ci-runner.awake</string>
  <key>ProgramArguments</key><array><string>/usr/bin/caffeinate</string><string>-s</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>"
fi
# xcode-upkeep.sh starts the runners once Xcode is ready (on a laptop through the power
# switch); until then GitHub sees them offline.
sdk="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showsdks 2>/dev/null |
    sed -nE 's/.*-sdk iphonesimulator([0-9.]+).*/\1/p' | tail -1)"
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS $sdk "; then
    for slot in $(seq 1 "$runner_count"); do launchctl bootout "system/$(slot_label "$slot")" 2>/dev/null || true; done
    echo "runners wait for the iOS $sdk runtime; de.iphoneblog.ci-runner.xcode starts them (/var/log/ci-runner-xcode.log)"
fi

step "done"
echo "$runner_count runners run as $user. Check: gh api repos/$repo/actions/runners --jq '.runners[] | {name,status,busy}'"
