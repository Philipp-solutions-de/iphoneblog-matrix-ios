#!/usr/bin/env bash
# Builds, tests and simulators at the lowest CPU priority on Thorsten's Mac (Thorsten,
# 2026-11-21), so a test run never slows the machine he works on. Sourced by build.sh and
# perf.sh:
#
#   lowprio xcodebuild …        runs a command with `taskpolicy -b` (background priority)
#   lower_simulator [udid]      lowers the build services and, given a udid, that simulator's
#                               process tree
#   lower_start [udid]          keeps lowering them every 20 s, so the app and the test runner
#   lower_stop                  the simulator starts later are lowered too; lower_stop ends it
#   raise_simulator udid        moves that simulator's process tree back to normal priority:
#                               ending the loop leaves lowered processes lowered, and perf.sh
#                               measured a simulator it had lowered while building (858 ms/s
#                               hitches against 14, 2026-11-22)
#
# GitHub's hosted runners keep normal priority: nobody works on them, and CI time counts.
# IPHONEBLOG_PRIORITY=normal turns it off anywhere; perf.sh measures at normal priority.

lowprio_on() {
    # The Mac Studio is only a fallback runner and Thorsten's own machine: always low there.
    if [[ "${RUNNER_NAME:-}" != mac-studio && "${RUNNER_NAME:-}" != mac-studio-* ]]; then
        [[ "${IPHONEBLOG_PRIORITY:-low}" != normal ]] || return 1
    fi
    [[ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]] || return 1
    command -v taskpolicy >/dev/null
}

lowprio() {
    if lowprio_on; then taskpolicy -b "$@"; else "$@"; fi
}

# Every descendant of a process, depth first.
lowprio_tree() {
    local pid
    for pid in $(pgrep -P "$1" 2>/dev/null); do
        echo "$pid"
        lowprio_tree "$pid"
    done
}

lower_simulator() {
    lowprio_on || return 0
    local udid="${1:-}" pid p
    # No udid, no simulator: never every simulator on the machine, other sessions' included.
    [[ -n "$udid" ]] && for pid in $(pgrep -f "launchd_sim.*${udid}" 2>/dev/null); do
        for p in "$pid" $(lowprio_tree "$pid"); do taskpolicy -b -p "$p" 2>/dev/null || true; done
    done
    for pid in $(pgrep -x XCBBuildService 2>/dev/null) $(pgrep -x SWBBuildService 2>/dev/null); do
        taskpolicy -b -p "$pid" 2>/dev/null || true
    done
}

raise_simulator() {
    local udid="${1:-}" pid p
    [[ -n "$udid" ]] || return 0
    for pid in $(pgrep -f "launchd_sim.*${udid}" 2>/dev/null); do
        for p in "$pid" $(lowprio_tree "$pid"); do taskpolicy -B -p "$p" 2>/dev/null || true; done
    done
    return 0
}

lower_start() {
    lowprio_on || return 0
    lower_stop
    # $$ is the calling script: the loop ends with it, also when it is stopped or fails.
    ( while kill -0 $$ 2>/dev/null; do lower_simulator "${1:-}"; sleep 20; done ) &
    LOWPRIO_LOOP=$!
}

lower_stop() {
    [[ -n "${LOWPRIO_LOOP:-}" ]] && kill "$LOWPRIO_LOOP" 2>/dev/null
    LOWPRIO_LOOP=
    return 0
}
