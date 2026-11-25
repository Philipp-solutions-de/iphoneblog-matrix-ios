#!/usr/bin/env bash
# Copy this Mac's Xcode and its iOS simulator runtime to another runner Mac over ssh
# (docs/mac-runner.md, "Xcode"). Run it on the Mac Studio, as Thorsten:
#
#   scripts/mac-runner/copy-xcode.sh mbp
#
# Why a copy: on the MacBook Pro every App Store install asks for Thorsten's password, and
# `xcodebuild -downloadPlatform iOS` fails there as root ("DVTDownloadable: Download Failed",
# 2026-11-25). The target needs passwordless sudo for its admin user while this runs. Then
# de.iphoneblog.ci-runner.xcode on the target accepts the licence, runs first launch and starts
# the runners (through the power switch on a laptop).
set -euo pipefail
host="${1:?usage: $0 <ssh host>}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

version="$(defaults read /Applications/Xcode.app/Contents/version.plist CFBundleShortVersionString)"
there="$(ssh -o BatchMode=yes "$host" 'defaults read /Applications/Xcode.app/Contents/version.plist CFBundleShortVersionString 2>/dev/null || echo none')"
ssh -o BatchMode=yes "$host" 'sudo -n true' || { echo "$host: no passwordless sudo." >&2; exit 1; }

if [[ "$there" != "$version" ]]; then
    echo "Xcode $version → $host (had $there)"
    ssh -o BatchMode=yes "$host" 'sudo -n rm -rf /Applications/Xcode.app.new && sudo -n mkdir /Applications/Xcode.app.new && sudo -n chown "$(id -un)" /Applications/Xcode.app.new'
    tar -C /Applications -cf - Xcode.app | ssh -o BatchMode=yes "$host" \
        'tar -xf - -C /Applications/Xcode.app.new && codesign --verify /Applications/Xcode.app.new/Xcode.app &&
         sudo -n rm -rf /Applications/Xcode.app && sudo -n mv /Applications/Xcode.app.new/Xcode.app /Applications/Xcode.app &&
         sudo -n rmdir /Applications/Xcode.app.new'
else
    echo "$host has Xcode $version already"
fi

# The runtime that matches the SDK: the disk image MobileAsset downloaded here.
sdk="$(xcodebuild -showsdks | sed -nE 's/.*-sdk iphonesimulator([0-9.]+).*/\1/p' | tail -1)"
if ssh -o BatchMode=yes "$host" "DEVELOPER_DIR=$DEVELOPER_DIR xcrun simctl list runtimes" | grep -q "^iOS $sdk "; then
    echo "$host has the iOS $sdk runtime already"
else
    dmg="$(xcrun simctl runtime list -j | python3 -c "
import json, sys
for r in json.load(sys.stdin).values():
    if r.get('version') == '$sdk' and r.get('state') == 'Ready':
        p = r['path']
        print(p if p.endswith('.dmg') else '')
        break" )"
    if [[ -z "$dmg" ]]; then
        dmg="$(find "$(xcrun simctl runtime list -j | python3 -c "
import json, sys
print(next(r['path'] for r in json.load(sys.stdin).values() if r.get('version') == '$sdk' and r.get('state') == 'Ready'))")" -name '*.dmg' | head -1)"
    fi
    [[ -f "$dmg" ]] || { echo "No iOS $sdk runtime image on this Mac." >&2; exit 1; }
    sum="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
    echo "iOS $sdk runtime → $host ($(du -h "$dmg" | cut -f1))"
    ssh -o BatchMode=yes "$host" "cat > /Users/Shared/ios-runtime.dmg" < "$dmg"
    ssh -o BatchMode=yes "$host" "echo '$sum  /Users/Shared/ios-runtime.dmg' | shasum -a 256 -c &&
        sudo -n env DEVELOPER_DIR=$DEVELOPER_DIR xcrun simctl runtime add /Users/Shared/ios-runtime.dmg;
        rm -f /Users/Shared/ios-runtime.dmg"
fi
ssh -o BatchMode=yes "$host" 'sudo -n launchctl kickstart -k system/de.iphoneblog.ci-runner.xcode' &&
    echo "de.iphoneblog.ci-runner.xcode runs on $host (/var/log/ci-runner-xcode.log)"
