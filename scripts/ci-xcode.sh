#!/usr/bin/env bash
# Prepare Xcode for a CI job, on GitHub's runner or the Mac Studio (docs/mac-runner.md, "Xcode").
# GitHub: select the newest Xcode $XCODE_MAJOR.x. Mac Studio: its user has no sudo, its .env sets
# DEVELOPER_DIR; check the version and the iOS runtime, give the job its runner instance's ports
# when the .env names none, and end servers a cancelled job left behind on them.
set -euo pipefail
: "${XCODE_MAJOR:?}"

if [[ "${RUNNER_ENVIRONMENT:-}" != self-hosted ]]; then
    xcode="$(ls -d /Applications/Xcode_"${XCODE_MAJOR}"*.app 2>/dev/null | sort -V | tail -1)"
    [[ -n "$xcode" ]] || { ls -d /Applications/Xcode*; exit 1; }
    sudo xcode-select -s "$xcode"
    xcodebuild -version
    exit 0
fi

xcodebuild -version
version="$(xcodebuild -version | sed -n 's/^Xcode //p')"
[[ "${version%%.*}" == "$XCODE_MAJOR" ]] ||
    { echo "::error::The Mac Studio has Xcode $version, the workflow wants $XCODE_MAJOR.x"; exit 1; }
sdk="$(xcodebuild -showsdks | sed -nE 's/.*-sdk iphonesimulator([0-9.]+).*/\1/p' | tail -1)"
xcrun simctl list runtimes | grep "^iOS $sdk " ||
    { echo "::error::No iOS $sdk simulator runtime on the Mac Studio (docs/mac-runner.md, Xcode)"; exit 1; }

# Thorsten's local test runs on this Mac hold 8008 and 8793; each runner instance has its own
# pair in its .env (setup.sh). A runner set up before that gets the first instance's.
if [[ -z "${TEST_HOMESERVER_PORT:-}" ]]; then
    TEST_HOMESERVER_PORT=18018 FIXTURE_PORT=18019
    { echo "TEST_HOMESERVER_PORT=$TEST_HOMESERVER_PORT"; echo "FIXTURE_PORT=$FIXTURE_PORT"; } >> "$GITHUB_ENV"
fi
for port in "$TEST_HOMESERVER_PORT" "${FIXTURE_PORT:-}"; do
    [[ -n "$port" ]] || continue
    pids="$(lsof -a -ti "tcp:$port" -sTCP:LISTEN -u "$(id -un)" 2>/dev/null || true)"
    [[ -z "$pids" ]] || { echo "ending a leftover server on $port: $pids"; kill $pids; }
done
