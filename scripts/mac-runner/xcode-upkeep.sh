#!/bin/sh
# Keep Xcode usable for the CI runner. Runs as root from the LaunchDaemon
# de.iphoneblog.ci-runner.xcode at load and daily at 05:10 (docs/mac-runner.md, "Xcode").
# After the App Store updates /Applications/Xcode.app it accepts the licence, installs the
# first-launch packages and downloads the iOS simulator runtime that matches the new SDK.
set -eu
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
log() { echo "$(date '+%F %T') $*"; }

xcodebuild -license check >/dev/null 2>&1 || { xcodebuild -license accept; log "licence accepted"; }
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || { xcodebuild -runFirstLaunch; log "first launch done"; }

sdk="$(xcodebuild -showsdks 2>/dev/null | sed -nE 's/.*-sdk iphonesimulator([0-9.]+).*/\1/p' | tail -1)"
[ -n "$sdk" ] || { log "no iOS simulator SDK"; exit 1; }
if xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS $sdk "; then
    log "Xcode $(xcodebuild -version | head -1 | cut -d' ' -f2), iOS $sdk runtime present"
    exit 0
fi
log "downloading the iOS $sdk simulator runtime"
xcodebuild -downloadPlatform iOS
xcrun simctl list runtimes | grep "^iOS $sdk " || { log "iOS $sdk runtime still missing"; exit 1; }
