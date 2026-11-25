#!/bin/sh
# Keep Xcode usable for the CI runner. Runs as root from the LaunchDaemon
# de.iphoneblog.ci-runner.xcode at load, daily at 05:10, and whenever Xcode's version.plist
# changes, i.e. right after the App Store updates Xcode (docs/mac-runner.md, "Xcode").
# It accepts the licence, installs the first-launch packages and downloads the iOS simulator
# runtime that matches the SDK. While Xcode is not ready it stops the runner: GitHub then sees
# it offline and build.yml sends every job to GitHub's runner instead of failing it here.
set -eu
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
log() { echo "$(date '+%F %T') $*"; }
# The runner instances: de.iphoneblog.ci-runner, de.iphoneblog.ci-runner-2 … (setup.sh).
runners() {
    for plist in /Library/LaunchDaemons/de.iphoneblog.ci-runner.plist /Library/LaunchDaemons/de.iphoneblog.ci-runner-[0-9]*.plist; do
        [ -f "$plist" ] && basename "$plist" .plist
    done
}
ready="/Library/Application Support/ci-runner/xcode-ready"
power_switch="/Library/Application Support/ci-runner/power-switch.sh"
stop_runner() {
    rm -f "$ready"
    for r in $(runners); do
        if launchctl print "system/$r" >/dev/null 2>&1; then launchctl bootout "system/$r"; log "$r stopped until Xcode is ready"; fi
    done
}
start_runner() {
    for r in $(runners); do
        if ! launchctl print "system/$r" >/dev/null 2>&1; then launchctl bootstrap system "/Library/LaunchDaemons/$r.plist"; log "$r started"; fi
    done
}

# The App Store writes the new Xcode in place; wait until the bundle stops changing.
sleep 60

if ! xcodebuild -license check >/dev/null 2>&1; then
    stop_runner; xcodebuild -license accept; log "licence accepted"
fi
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    stop_runner; xcodebuild -runFirstLaunch; log "first launch done"
fi

sdk="$(xcodebuild -showsdks 2>/dev/null | sed -nE 's/.*-sdk iphonesimulator([0-9.]+).*/\1/p' | tail -1)"
if [ -z "$sdk" ]; then stop_runner; log "no iOS simulator SDK"; exit 1; fi
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS $sdk "; then
    stop_runner
    log "downloading the iOS $sdk simulator runtime"
    xcodebuild -downloadPlatform iOS 2>&1 | tr '\r' '\n' | grep -v '% (' || true
    xcrun simctl list runtimes | grep -q "^iOS $sdk " || { log "iOS $sdk runtime still missing"; exit 1; }
fi
log "Xcode $(xcodebuild -version | head -1 | cut -d' ' -f2), iOS $sdk runtime present"
touch "$ready"
# On a laptop the power switch decides: it starts the runners only on power (power-switch.sh).
if [ -x "$power_switch" ]; then "$power_switch"; else start_runner; fi
