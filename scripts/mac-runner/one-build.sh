#!/usr/bin/env bash
# One build at a time on a self-hosted Mac (docs/mac-runner.md, "Test shards"):
#
#   scripts/mac-runner/one-build.sh scripts/build.sh build-for-testing
#
# Two runs on one Mac share the user ci and with it one Xcode build service (SWBBuildService).
# When two `xcodebuild build-for-testing` ran at once on the MacBook Pro on 2026-11-25, one of
# them waited 42 minutes for a service that no longer answered it, until its timeout. So a build
# waits here until the other has finished. Test shards (test-without-building) do not build and
# need no lock. On GitHub's runners every job is its own machine: the command runs at once.
set -euo pipefail
(( $# > 0 )) || { echo "usage: $0 <command> [args…]" >&2; exit 2; }
if [[ "${RUNNER_ENVIRONMENT:-}" != self-hosted ]]; then exec "$@"; fi

lock="$HOME/.ci-build-lock"
waited=0
until mkdir "$lock" 2>/dev/null; do
    holder="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
        echo "the build lock's holder $holder is gone; taking it over"
        rm -rf "$lock"
        continue
    fi
    (( waited % 60 == 0 )) && echo "another build runs on this Mac (pid ${holder:-?}); waiting (${waited} s)"
    sleep 10
    waited=$(( waited + 10 ))
done
echo $$ > "$lock/pid"
trap 'rm -rf "$lock"' EXIT
(( waited == 0 )) || echo "waited ${waited} s for the other build"
"$@"
