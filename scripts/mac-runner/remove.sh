#!/usr/bin/env bash
# Remove the self-hosted runner from this Mac in one step (docs/mac-runner.md, "Removal").
#
#   scripts/mac-runner/remove.sh                 unregister, stop and remove the services
#   scripts/mac-runner/remove.sh --delete-user   the same, then delete the user `ci` and its home
#   --machine mbp                                the label setup.sh used (default mac-studio)
#
# Run it as the Mac's admin user, not with sudo. It unregisters the runner with your `gh` login
# and asks for your password once. CI goes on: build.yml sends every job to GitHub's runner as
# soon as this one is gone. The home folders setup.sh closed stay closed; the modes they had are
# in "/Library/Application Support/ci-runner/home-modes" until this script deletes that folder,
# and it prints them first.
set -euo pipefail

repo="Philipp-solutions-de/iphoneblog-matrix-ios"
user="ci"
machine="mac-studio"   # the instances <machine>, <machine>-2 … (setup.sh)
support="/Library/Application Support/ci-runner"

if [[ "${1:-}" != "--as-root" ]]; then
    [[ "$(id -u)" != 0 ]] || { echo "Run this as yourself, not with sudo." >&2; exit 1; }
    delete_user="no"
    while (( $# )); do
        case "$1" in
        --delete-user) delete_user="yes"; shift ;;
        --machine) machine="$2"; shift 2 ;;
        *) echo "usage: $0 [--machine <label>] [--delete-user]" >&2; exit 2 ;;
        esac
    done
    token_file="$(mktemp)"
    chmod 600 "$token_file"
    trap 'rm -f "$token_file"' EXIT
    gh api -X POST "repos/$repo/actions/runners/remove-token" --jq .token > "$token_file" || true
    echo "Now sudo asks for your Mac password."
    sudo "$0" --as-root "$token_file" "$delete_user"
    # A runner may already be gone from the Mac but still listed on GitHub (offline).
    for id_ in $(gh api "repos/$repo/actions/runners" --jq ".runners[] | select(.name == \"$machine\" or (.name | test(\"^$machine-[0-9]+$\"))) | .id" || true); do
        gh api -X DELETE "repos/$repo/actions/runners/$id_" && echo "deleted runner $id_ on GitHub"
    done
    echo "Runner removed. GitHub lists: $(gh api "repos/$repo/actions/runners" --jq '[.runners[].name] | join(", ")')"
    exit 0
fi

token_file="$2"
delete_user="$3"
for plist in /Library/LaunchDaemons/de.iphoneblog.ci-runner*.plist; do
    [[ -f "$plist" ]] || continue
    label="$(basename "$plist" .plist)"
    launchctl bootout "system/$label" 2>/dev/null && echo "stopped $label" || true
    rm -f "$plist"
done
# Jobs leave simulators and test servers running under the user; end them.
if id "$user" >/dev/null 2>&1; then
    pkill -u "$user" 2>/dev/null || true
fi

for dir in /Users/"$user"/actions-runner /Users/"$user"/actions-runner-*; do
    if [[ -f "$dir/.runner" && -s "$token_file" ]]; then
        (cd "$dir" && sudo -u "$user" -H ./config.sh remove --token "$(cat "$token_file")") || true
    fi
done

/sbin/pfctl -a com.apple/ci-runner -F all 2>/dev/null && echo "network wall removed" || true

if [[ -f "$support/home-modes" ]]; then
    echo "Home folders before setup.sh (restore with chmod if you want them open again):"
    sed 's/^/  /' "$support/home-modes"
fi
rm -rf "$support"
rm -f /var/log/ci-runner-pf.log /var/log/ci-runner-xcode.log /var/log/ci-runner-power.log

if [[ "$delete_user" == "yes" ]] && dscl . -read "/Users/$user" UniqueID >/dev/null 2>&1; then
    dseditgroup -o edit -d "$user" -t user _developer 2>/dev/null || true
    dscl . -delete "/Users/$user"
    dscl . -delete "/Groups/$user" 2>/dev/null || true
    rm -rf "/Users/$user"
    echo "deleted user $user and /Users/$user"
fi
