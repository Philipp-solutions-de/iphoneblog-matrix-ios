#!/usr/bin/env bash
# Light and dark screenshots of every tab, signed out and signed in, on one simulator.
#   scripts/screenshots.sh <simulator-udid> <blog-api-url> [out-dir]
# Signed in uses the test server (scripts/test-homeserver.sh start) and its #one alias.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dev="$1"; api="$2"; out="${3:-$here/build/shots/tabs}"
app="$here/build/DerivedData/Build/Products/Debug-iphonesimulator/iphoneblog.app"
id="de.iphoneblog.matrix.preview"
mkdir -p "$out"
xcrun simctl install "$dev" "$app"
set -a; . "$here/build/test-homeserver.env"; set +a
shoot() { # mode who tab
    xcrun simctl ui "$dev" appearance "$1"
    xcrun simctl terminate "$dev" "$id" 2>/dev/null || true
    local extra=()
    if [[ "$2" == member ]]; then
        extra=(SIMCTL_CHILD_IPHONEBLOG_HOMESERVER="$IPHONEBLOG_TEST_HOMESERVER"
               SIMCTL_CHILD_IPHONEBLOG_DEV_USER="$IPHONEBLOG_TEST_USER"
               SIMCTL_CHILD_IPHONEBLOG_DEV_PASSWORD="$IPHONEBLOG_TEST_PASSWORD"
               SIMCTL_CHILD_IPHONEBLOG_ONE_ALIAS="$IPHONEBLOG_ONE_ALIAS"
               SIMCTL_CHILD_IPHONEBLOG_BLOG_ALIAS="$IPHONEBLOG_BLOG_ALIAS")
    else
        xcrun simctl keychain "$dev" reset
    fi
    env ${extra[@]+"${extra[@]}"} SIMCTL_CHILD_IPHONEBLOG_BLOG_API="$api" SIMCTL_CHILD_IPHONEBLOG_START_TAB="$3" \
        xcrun simctl launch "$dev" "$id" >/dev/null
    sleep 14
    xcrun simctl io "$dev" screenshot "$out/$2-$3-$1.png" >/dev/null 2>&1
}
for mode in light dark; do
    for tab in blog chat mentions me; do shoot "$mode" guest "$tab"; done
    for tab in blog chat mentions me; do shoot "$mode" member "$tab"; done
done
xcrun simctl keychain "$dev" reset
echo "screenshots: $out"
