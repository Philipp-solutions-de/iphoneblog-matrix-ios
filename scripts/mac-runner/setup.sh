#!/usr/bin/env bash
# Set up the self-hosted GitHub Actions runner on the Mac Studio (docs/mac-runner.md).
#
#   scripts/mac-runner/setup.sh
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
#   6. downloads the Actions runner (checksum checked), registers it for this one repository
#      with the label `mac-studio`, and starts it as a LaunchDaemon under `ci`
set -euo pipefail

repo="Philipp-solutions-de/iphoneblog-matrix-ios"
user="ci"
runner_name="mac-studio"
labels="mac-studio"
runner_version="2.338.2"
runner_sha256="25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388"
support="/Library/Application Support/ci-runner"
here="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" != "--as-root" ]]; then
    [[ "$(id -u)" != 0 ]] || { echo "Run this as yourself, not with sudo." >&2; exit 1; }
    [[ "$(uname -m)" == arm64 ]] || { echo "This is for the Apple-silicon Mac Studio." >&2; exit 1; }
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
    if [[ ! -f "/Users/$user/actions-runner/.runner" ]]; then
        # Prints nothing: the token goes straight into a file only root and you can read.
        gh api -X POST "repos/$repo/actions/runners/registration-token" --jq .token > "$token_file"
        [[ -s "$token_file" ]] || { echo "No registration token (gh login with admin on $repo?)." >&2; exit 1; }
    fi
    echo "Now sudo asks for your Mac password."
    sudo "$0" --as-root "$token_file"
    exit 0
fi

token_file="${2:-}"
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
install_daemon() { # label, plist body
    local plist="/Library/LaunchDaemons/$1.plist"
    local tmp; tmp="$(mktemp)"
    printf '%s\n' "$2" > "$tmp"
    plutil -lint "$tmp" >/dev/null
    if ! cmp -s "$tmp" "$plist" 2>/dev/null; then
        launchctl bootout "system/$1" 2>/dev/null || true
        install -m 644 -o root -g wheel "$tmp" "$plist"
        launchctl bootstrap system "$plist"
        echo "$1 (re)loaded"
    else
        launchctl print "system/$1" >/dev/null 2>&1 || launchctl bootstrap system "$plist"
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
  <key>StandardOutPath</key><string>/var/log/ci-runner-xcode.log</string>
  <key>StandardErrorPath</key><string>/var/log/ci-runner-xcode.log</string>
</dict></plist>"

# 6. The runner.
step "runner"
dir="/Users/$user/actions-runner"
as_ci() { sudo -u "$user" -H "$@"; }
if [[ ! -x "$dir/config.sh" ]]; then
    tarball="/Users/$user/actions-runner-$runner_version.tar.gz"
    as_ci curl -fsSL -o "$tarball" \
        "https://github.com/actions/runner/releases/download/v$runner_version/actions-runner-osx-arm64-$runner_version.tar.gz"
    echo "$runner_sha256  $tarball" | shasum -a 256 -c -
    as_ci mkdir -p "$dir"
    as_ci tar -xzf "$tarball" -C "$dir"
    rm -f "$tarball"
fi
# What a job finds: the system tools, Xcode's python3 and git, and ~/.local/bin for uv.
as_ci sh -c "printf '%s\n' '/Users/$user/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin' > '$dir/.path'"
as_ci sh -c "printf '%s\n' 'LANG=en_US.UTF-8' 'DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer' > '$dir/.env'"
if [[ ! -f "$dir/.runner" ]]; then
    [[ -s "$token_file" ]] || { echo "No registration token." >&2; exit 1; }
    token="$(cat "$token_file")"
    (cd "$dir" && as_ci ./config.sh --unattended --replace \
        --url "https://github.com/$repo" --token "$token" \
        --name "$runner_name" --labels "$labels" --work _work)
    unset token
else
    echo "already registered"
fi
as_ci mkdir -p "/Users/$user/Library/Logs"
install_daemon de.iphoneblog.ci-runner "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>de.iphoneblog.ci-runner</string>
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
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/Users/$user/Library/Logs/actions-runner.log</string>
  <key>StandardErrorPath</key><string>/Users/$user/Library/Logs/actions-runner.log</string>
</dict></plist>"

step "done"
echo "Runner '$runner_name' runs as $user. Check: gh api repos/$repo/actions/runners --jq '.runners[] | {name,status,busy}'"
