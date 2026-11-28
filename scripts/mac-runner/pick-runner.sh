#!/usr/bin/env bash
# Decide where "Build and test" runs: one of the self-hosted Macs or GitHub's hosted runner
# (docs/mac-runner.md, "Which runner"). Called by the job "Pick a runner" in build.yml;
# prints `runs-on=<json>`, `where=mac|hosted` and `machine=<label>|hosted` for $GITHUB_OUTPUT
# and the reason on stderr.
#
# Input, all from the environment:
#   EVENT_NAME     github.event_name
#   HEAD_REPO      github.event.pull_request.head.repo.full_name (empty unless pull_request)
#   REPO           github.repository
#   MAC_RUNNER     the repository variable: "off" sends every job to GitHub
#   MAC_MACHINES   the Macs, first the default and then the fallbacks (default "mbp mac-studio":
#                  the MacBook Pro, the Mac Studio only when it is away); each is a runner label
#                  and name prefix
#   STATUS_TOKEN   a token that may read the repository's runners (Administration: read)
#   FALLBACK_MINUTES  how long the default Mac may be offline before a fallback takes the run
#                  (default 30)
#   RUNNERS_JSON   test hook: a file holding the API's answer instead of asking GitHub
set -euo pipefail

hosted='"xcode-27"'
read -r -a machines <<<"${MAC_MACHINES:-mbp mac-studio}"
fallback_minutes="${FALLBACK_MINUTES:-30}"
poll_seconds="${POLL_SECONDS:-30}"

title() { # label → what the reason calls it
    case "$1" in mbp) echo "the MacBook Pro" ;; mac-studio) echo "the Mac Studio" ;; *) echo "the Mac $1" ;; esac
}
answer() { # machine-label|hosted, reason
    echo "$2" >&2
    if [[ "$1" == hosted ]]; then
        echo "runs-on=$hosted"; echo "where=hosted"; echo "machine=hosted"
    else
        echo "runs-on=[\"self-hosted\",\"$1\"]"; echo "where=mac"; echo "machine=$1"
    fi
    exit 0
}
joined() { # separator, items… → "a, b" or "a and b"
    local sep="$1"; shift
    local out="" i
    for i in "$@"; do out="${out:+$out$sep}$i"; done
    echo "$out"
}

# Strangers' code never reaches a Mac. A pull request from a fork, or any event this list
# does not know, goes to GitHub. The weekly run stays there on purpose: it checks the hosted
# image the TestFlight job needs.
case "${EVENT_NAME:-}" in
push|workflow_dispatch) ;;
pull_request)
    [[ -n "${HEAD_REPO:-}" && "${HEAD_REPO}" == "${REPO:-}" ]] ||
        answer hosted "hosted: pull request from ${HEAD_REPO:-an unknown repository}, not $REPO"
    ;;
*) answer hosted "hosted: event ${EVENT_NAME:-none} always runs on GitHub" ;;
esac
[[ "${MAC_RUNNER:-}" != "off" ]] || answer hosted "hosted: repository variable MAC_RUNNER is off"
[[ -n "${STATUS_TOKEN:-}" || -n "${RUNNERS_JSON:-}" ]] ||
    answer hosted "hosted: no MAC_RUNNER_STATUS_TOKEN, so the Macs' state is unknown"

runners_json() {
    if [[ -n "${RUNNERS_JSON:-}" ]]; then
        cat "$RUNNERS_JSON"
    else
        curl -fsS -m 20 -H "Authorization: Bearer $STATUS_TOKEN" \
            -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/$REPO/actions/runners?per_page=100"
    fi
}
state_of() { # machine, json → "online busy", "online idle", "offline" or "missing"
    # A Mac's instances are named <label>, <label>-2 … (setup.sh). Idle means every online
    # instance is free: a run needs one for its build and then one per test shard. An instance
    # that is offline alone does not send the run away.
    jq -r --arg m "$1" '
        [.runners[] | select(.name == $m or (.name | test("^" + $m + "-[0-9]+$")))] as $r |
        [$r[] | select(.status == "online")] as $on |
        if ($r | length) == 0 then "missing"
        elif ($on | length) == 0 then "offline"
        elif any($on[]; .busy) then "online busy" else "online idle" end' <<<"$2"
}

# The first Mac is the default (Thorsten, 2026-11-25: the MacBook Pro; the Mac Studio is only a
# fallback, so a run there never slows the machine he works on). While the default is online,
# busy or not, the run goes to it and waits for a free instance there. Only when it has been
# offline for FALLBACK_MINUTES does a fallback take the run, and only one that is online and
# idle; otherwise GitHub. A default Mac that is not registered at all is skipped at once.
default="${machines[0]}"
fallbacks=("${machines[@]:1}")
deadline=$(( $(date +%s) + fallback_minutes * 60 ))
while :; do
    json="$(runners_json)" || answer hosted "hosted: GitHub's runner API did not answer (token expired?)"
    state="$(state_of "$default" "$json")"
    case "$state" in
    "online idle") answer "$default" "$default: $(title "$default") is online and idle" ;;
    "online busy") answer "$default" "$default: $(title "$default") is online; the run waits for a free instance there" ;;
    missing) break ;;
    esac
    (( $(date +%s) + poll_seconds <= deadline )) || break
    echo "$(title "$default") is offline; asking again in $poll_seconds s (fallback after $fallback_minutes minutes)" >&2
    sleep "$poll_seconds"
done
away="$(title "$default") is $state"
for m in "${fallbacks[@]}"; do
    fstate="$(state_of "$m" "$json")"
    [[ "$fstate" != "online idle" ]] ||
        answer "$m" "$m: $away, $(title "$m") is online and idle (fallback)"
    away="$away, $(title "$m") is $fstate"
done
answer hosted "hosted: $away"
