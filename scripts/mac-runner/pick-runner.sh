#!/usr/bin/env bash
# Decide where "Build and test" runs: the Mac Studio or GitHub's hosted runner
# (docs/mac-runner.md, "Which runner"). Called by the job "Pick a runner" in build.yml;
# prints `runs-on=<json>` and `where=mac|hosted` for $GITHUB_OUTPUT and the reason on stderr.
#
# Input, all from the environment:
#   EVENT_NAME     github.event_name
#   HEAD_REPO      github.event.pull_request.head.repo.full_name (empty unless pull_request)
#   REPO           github.repository
#   MAC_RUNNER     the repository variable: "off" sends every job to GitHub
#   STATUS_TOKEN   a token that may read the repository's runners (Administration: read)
#   WAIT_MINUTES   how long to wait for a busy Mac before going to GitHub (default 20)
#   RUNNERS_JSON   test hook: a file holding the API's answer instead of asking GitHub
set -euo pipefail

mac='["self-hosted","mac-studio"]'
hosted='"xcode-27"'
runner_prefix="mac-studio"   # the instances mac-studio, mac-studio-2 … (setup.sh)
wait_minutes="${WAIT_MINUTES:-20}"
poll_seconds="${POLL_SECONDS:-30}"

answer() { # where, reason
    echo "$1: $2" >&2
    if [[ "$1" == mac ]]; then echo "runs-on=$mac"; else echo "runs-on=$hosted"; fi
    echo "where=$1"
    exit 0
}

# Strangers' code never reaches the Mac. A pull request from a fork, or any event this list
# does not know, goes to GitHub. The weekly run stays there on purpose: it checks the hosted
# image the TestFlight job needs.
case "${EVENT_NAME:-}" in
push|workflow_dispatch) ;;
pull_request)
    [[ -n "${HEAD_REPO:-}" && "${HEAD_REPO}" == "${REPO:-}" ]] ||
        answer hosted "pull request from ${HEAD_REPO:-an unknown repository}, not $REPO"
    ;;
*) answer hosted "event ${EVENT_NAME:-none} always runs on GitHub" ;;
esac
[[ "${MAC_RUNNER:-}" != "off" ]] || answer hosted "repository variable MAC_RUNNER is off"

status() { # prints "online busy", "online idle", "offline" or "missing"; fails on an API error
    local json
    if [[ -n "${RUNNERS_JSON:-}" ]]; then
        json="$(cat "$RUNNERS_JSON")"
    else
        json="$(curl -fsS -m 20 -H "Authorization: Bearer $STATUS_TOKEN" \
            -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/$REPO/actions/runners?per_page=100")" || return 1
    fi
    # Idle means every online instance is free: a run needs one for its build and then one per
    # test shard. An instance that is offline alone does not send the run away.
    jq -r --arg p "$runner_prefix" '
        [.runners[] | select(.name | startswith($p))] as $r |
        [$r[] | select(.status == "online")] as $on |
        if ($r | length) == 0 then "missing"
        elif ($on | length) == 0 then "offline"
        elif any($on[]; .busy) then "online busy" else "online idle" end' <<<"$json"
}

[[ -n "${STATUS_TOKEN:-}" || -n "${RUNNERS_JSON:-}" ]] ||
    answer hosted "no MAC_RUNNER_STATUS_TOKEN, so the Mac's state is unknown"

deadline=$(( $(date +%s) + wait_minutes * 60 ))
while :; do
    state="$(status)" || answer hosted "GitHub's runner API did not answer (token expired?)"
    case "$state" in
    "online idle") answer mac "the Mac Studio is online and idle" ;;
    missing) answer hosted "no runner named $runner_prefix… is registered" ;;
    offline) answer hosted "the Mac Studio is offline" ;;
    esac
    (( $(date +%s) + poll_seconds <= deadline )) ||
        answer hosted "the Mac Studio stayed busy for $wait_minutes minutes"
    echo "the Mac Studio is busy; asking again in $poll_seconds s" >&2
    sleep "$poll_seconds"
done
