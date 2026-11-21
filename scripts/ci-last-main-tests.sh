#!/usr/bin/env bash
# Were the tests of the last finished main build red? Prints "red" or "green" (docs/mac-runner.md,
# "TestFlight"). A main build uploads to TestFlight right after it compiles; only when the build
# before it had red tests does the upload wait for its own tests, so a red test blocks the next
# upload and a fix still goes out once its own tests pass.
#
# Needs GH_TOKEN (actions: read), GITHUB_REPOSITORY and GITHUB_RUN_ID.
set -euo pipefail
runs="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/build.yml/runs?branch=main&event=push&status=completed&per_page=20" \
    --jq ".workflow_runs[] | select(.id != $GITHUB_RUN_ID) | \"\(.id) \(.conclusion)\"")"
while read -r id conclusion; do
    [[ -n "$id" ]] || continue
    case "$conclusion" in
    success) echo green; exit 0 ;;
    failure)
        # Red tests, or a build that did not compile; a failed upload alone is not a red test.
        if gh api "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs?per_page=50" \
            --jq '.jobs[] | select(.conclusion == "failure") | .name' |
            grep -qE '^(Tests|Build)'; then
            echo red
        else
            echo green
        fi
        exit 0 ;;
    esac  # cancelled or skipped: look further back
done <<< "$runs"
echo green
