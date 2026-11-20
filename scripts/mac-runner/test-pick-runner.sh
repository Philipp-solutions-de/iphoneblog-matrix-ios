#!/usr/bin/env bash
# Tests for pick-runner.sh, with the runner API's answer from a file. Runs in the job
# "Pick a runner" before the pick itself, and by hand: scripts/mac-runner/test-pick-runner.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
runner() { printf '{"total_count":1,"runners":[{"name":"mac-studio","status":"%s","busy":%s}]}' "$1" "$2" > "$tmp/$3"; }
runner online false idle.json
runner online true busy.json
runner offline false offline.json
echo '{"total_count":0,"runners":[]}' > "$tmp/none.json"
fails=0
check() { # expected-where, description, env...
    local want="$1" what="$2"; shift 2
    local got
    got="$(env -i PATH="$PATH" REPO=Philipp-solutions-de/iphoneblog-matrix-ios WAIT_MINUTES=0 POLL_SECONDS=1 "$@" \
        "$here/pick-runner.sh" 2>/dev/null | sed -n 's/^where=//p')"
    if [[ "$got" == "$want" ]]; then echo "ok   $what"; else echo "FAIL $what: want $want, got ${got:-nothing}"; fails=$((fails + 1)); fi
}
own=HEAD_REPO=Philipp-solutions-de/iphoneblog-matrix-ios
check mac    "push to main, Mac idle"              EVENT_NAME=push RUNNERS_JSON="$tmp/idle.json"
check mac    "own pull request, Mac idle"          EVENT_NAME=pull_request $own RUNNERS_JSON="$tmp/idle.json"
check mac    "hand run, Mac idle"                  EVENT_NAME=workflow_dispatch RUNNERS_JSON="$tmp/idle.json"
check hosted "fork pull request, Mac idle"         EVENT_NAME=pull_request HEAD_REPO=someone/iphoneblog-matrix-ios RUNNERS_JSON="$tmp/idle.json"
check hosted "pull request without a head repo"    EVENT_NAME=pull_request RUNNERS_JSON="$tmp/idle.json"
check hosted "pull_request_target"                 EVENT_NAME=pull_request_target $own RUNNERS_JSON="$tmp/idle.json"
check hosted "weekly schedule"                     EVENT_NAME=schedule RUNNERS_JSON="$tmp/idle.json"
check hosted "MAC_RUNNER=off"                      EVENT_NAME=push MAC_RUNNER=off RUNNERS_JSON="$tmp/idle.json"
check hosted "Mac offline"                         EVENT_NAME=push RUNNERS_JSON="$tmp/offline.json"
check hosted "Mac not registered"                  EVENT_NAME=push RUNNERS_JSON="$tmp/none.json"
check hosted "Mac busy past the wait"              EVENT_NAME=push RUNNERS_JSON="$tmp/busy.json"
check hosted "no status token"                     EVENT_NAME=push
check hosted "API error"                           EVENT_NAME=push STATUS_TOKEN=bad RUNNERS_JSON=
(( fails == 0 )) || { echo "$fails failed"; exit 1; }
