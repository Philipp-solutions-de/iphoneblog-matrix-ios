#!/usr/bin/env bash
# Tests for pick-runner.sh, with the runner API's answer from a file. Runs in the job
# "Pick a runner" before the pick itself, and by hand: scripts/mac-runner/test-pick-runner.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# runners <file> <name:status:busy>… → the API's answer
runners() {
    local file="$1"; shift
    local items="" n s b r
    for r in "$@"; do
        IFS=: read -r n s b <<<"$r"
        items="${items:+$items,}{\"name\":\"$n\",\"status\":\"$s\",\"busy\":$b}"
    done
    printf '{"runners":[%s]}' "$items" > "$tmp/$file"
}
runners idle.json        mac-studio:online:false
runners busy.json        mac-studio:online:true
runners offline.json     mac-studio:offline:false
runners none.json
runners one-busy.json    mac-studio:online:false mac-studio-2:online:true
runners one-off.json     mac-studio:offline:false mac-studio-2:online:false
runners other.json       other:online:false
runners both-idle.json   mbp:online:false mbp-2:online:false mac-studio:online:false
runners mbp-busy.json    mbp:online:false mbp-2:online:true mac-studio:online:false
runners mbp-off.json     mbp:offline:false mbp-2:offline:false mac-studio:online:false
runners mbp-only.json    mbp:online:false
runners both-off.json    mbp:offline:false mac-studio:offline:false
runners both-busy.json   mbp:online:true mac-studio:online:true
runners studio-busy.json mbp:offline:false mac-studio:online:true
runners prefix.json      mbpx:online:false mac-studio-old:online:false
fails=0
check() { # expected machine label or hosted, description, env...
    local want="$1" what="$2"; shift 2
    local out want_where=mac want_runs_on
    out="$(env -i PATH="$PATH" REPO=Philipp-solutions-de/iphoneblog-matrix-ios FALLBACK_MINUTES=0 POLL_SECONDS=1 "$@" \
        "$here/pick-runner.sh" 2>/dev/null)"
    if [[ "$want" == hosted ]]; then want_where=hosted; want_runs_on='"xcode-27"'
    else want_runs_on="[\"self-hosted\",\"$want\"]"; fi
    if grep -qx "machine=$want" <<<"$out" && grep -qx "where=$want_where" <<<"$out" &&
       grep -qxF "runs-on=$want_runs_on" <<<"$out"; then
        echo "ok   $what"
    else
        echo "FAIL $what: want $want, got $(sed -n 's/^machine=//p' <<<"$out")"; fails=$((fails + 1))
    fi
}
own=HEAD_REPO=Philipp-solutions-de/iphoneblog-matrix-ios
check mac-studio "push to main, Studio idle"              EVENT_NAME=push RUNNERS_JSON="$tmp/idle.json"
check mac-studio "own pull request, Studio idle"          EVENT_NAME=pull_request $own RUNNERS_JSON="$tmp/idle.json"
check mac-studio "hand run, Studio idle"                  EVENT_NAME=workflow_dispatch RUNNERS_JSON="$tmp/idle.json"
check hosted     "fork pull request, Macs idle"           EVENT_NAME=pull_request HEAD_REPO=someone/iphoneblog-matrix-ios RUNNERS_JSON="$tmp/both-idle.json"
check hosted     "pull request without a head repo"       EVENT_NAME=pull_request RUNNERS_JSON="$tmp/both-idle.json"
check hosted     "pull_request_target"                    EVENT_NAME=pull_request_target $own RUNNERS_JSON="$tmp/both-idle.json"
check hosted     "weekly schedule"                        EVENT_NAME=schedule RUNNERS_JSON="$tmp/both-idle.json"
check hosted     "MAC_RUNNER=off"                         EVENT_NAME=push MAC_RUNNER=off RUNNERS_JSON="$tmp/both-idle.json"
check hosted     "Studio offline, no MBP"                 EVENT_NAME=push RUNNERS_JSON="$tmp/offline.json"
check hosted     "no Mac registered"                      EVENT_NAME=push RUNNERS_JSON="$tmp/none.json"
check hosted     "no MBP, Studio busy"                    EVENT_NAME=push RUNNERS_JSON="$tmp/busy.json"
check hosted     "one of the Studio's instances busy"     EVENT_NAME=push RUNNERS_JSON="$tmp/one-busy.json"
check mac-studio "one instance offline, the rest idle"    EVENT_NAME=push RUNNERS_JSON="$tmp/one-off.json"
check hosted     "only other runners registered"          EVENT_NAME=push RUNNERS_JSON="$tmp/other.json"
check hosted     "names that only start like a Mac's"     EVENT_NAME=push RUNNERS_JSON="$tmp/prefix.json"
check mbp        "both idle: the MacBook Pro first"       EVENT_NAME=push RUNNERS_JSON="$tmp/both-idle.json"
check mbp        "MacBook Pro busy: it still takes the run" EVENT_NAME=push RUNNERS_JSON="$tmp/mbp-busy.json"
check mac-studio "MacBook Pro offline past the fallback"  EVENT_NAME=push RUNNERS_JSON="$tmp/mbp-off.json"
check mbp        "only the MacBook Pro registered"        EVENT_NAME=push RUNNERS_JSON="$tmp/mbp-only.json"
check hosted     "both Macs offline"                      EVENT_NAME=push RUNNERS_JSON="$tmp/both-off.json"
check mbp        "both Macs busy: the MacBook Pro"        EVENT_NAME=push RUNNERS_JSON="$tmp/both-busy.json"
check hosted     "MBP offline, Studio busy"               EVENT_NAME=push RUNNERS_JSON="$tmp/studio-busy.json"
check mac-studio "MAC_MACHINES=mac-studio skips the MBP"  EVENT_NAME=push MAC_MACHINES=mac-studio RUNNERS_JSON="$tmp/both-idle.json"
check mac-studio "MAC_MACHINES=mac-studio, busy: it waits"  EVENT_NAME=push MAC_MACHINES=mac-studio RUNNERS_JSON="$tmp/busy.json"
check hosted     "no status token"                        EVENT_NAME=push
check hosted     "API error"                              EVENT_NAME=push STATUS_TOKEN=bad RUNNERS_JSON=
(( fails == 0 )) || { echo "$fails failed"; exit 1; }
