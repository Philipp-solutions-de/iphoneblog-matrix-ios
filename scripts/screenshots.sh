#!/usr/bin/env bash
# Light and dark screenshots of each screen in the design previews, on one simulator.
#   scripts/screenshots.sh <simulator-udid> <blog-api-url> <blog-web-url> [out-dir]
# Signed in uses the test server (scripts/test-homeserver.sh start). <blog-api-url> serves
# threads.json, threads/ and links.json; <blog-web-url> the blog's app view.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dev="$1"; api="$2"; web="$3"; out="${4:-$here/build/shots/screens}"
app="$here/build/DerivedData/Build/Products/Debug-iphonesimulator/iphoneblog.app"
id="de.iphoneblog.matrix.preview"
mkdir -p "$out"
xcrun simctl install "$dev" "$app"
set -a; . "$here/build/test-homeserver.env"; set +a
shoot() { # mode who tab name [VAR=value ...]
    local mode="$1" who="$2" tab="$3" name="$4"; shift 4
    xcrun simctl ui "$dev" appearance "$mode"
    xcrun simctl terminate "$dev" "$id" 2>/dev/null || true
    local extra=()
    if [[ "$who" == member ]]; then
        extra=(SIMCTL_CHILD_IPHONEBLOG_HOMESERVER="$IPHONEBLOG_TEST_HOMESERVER"
               SIMCTL_CHILD_IPHONEBLOG_DEV_USER="$IPHONEBLOG_TEST_USER"
               SIMCTL_CHILD_IPHONEBLOG_DEV_PASSWORD="$IPHONEBLOG_TEST_PASSWORD"
               SIMCTL_CHILD_IPHONEBLOG_ONE_ALIAS="$IPHONEBLOG_ONE_ALIAS"
               SIMCTL_CHILD_IPHONEBLOG_BLOG_ALIAS="$IPHONEBLOG_BLOG_ALIAS"
               SIMCTL_CHILD_IPHONEBLOG_CHANNEL_ALIAS="$IPHONEBLOG_CHANNEL_ALIAS")
    else
        xcrun simctl keychain "$dev" reset
    fi
    for pair in "$@"; do extra+=("SIMCTL_CHILD_$pair"); done
    env ${extra[@]+"${extra[@]}"} SIMCTL_CHILD_IPHONEBLOG_BLOG_API="$api" SIMCTL_CHILD_IPHONEBLOG_BLOG_WEB="$web" \
        SIMCTL_CHILD_IPHONEBLOG_START_TAB="$tab" xcrun simctl launch "$dev" "$id" >/dev/null
    sleep 14
    xcrun simctl io "$dev" screenshot "$out/$name-$mode.png" >/dev/null 2>&1
}
# The mock's first article; its thread file is threads/<root>.json under <blog-api-url>.
guest_root="${GUEST_ROOT:-\$article0}"
for mode in light dark; do
    shoot "$mode" guest  blog     1-blog-guest
    shoot "$mode" member blog     2a-discussion-member "IPHONEBLOG_START_DISCUSSION=$IPHONEBLOG_TEST_ARTICLE_ROOT"
    shoot "$mode" guest  blog     2b-discussion-reader "IPHONEBLOG_START_DISCUSSION=$guest_root"
    shoot "$mode" member chat     3a-one-chat
    shoot "$mode" member chat     3b-one-chat-thread "IPHONEBLOG_START_THREAD=$IPHONEBLOG_TEST_CHANNEL_ROOM|$IPHONEBLOG_TEST_CHANNEL_THREAD"
    shoot "$mode" guest  chat     3c-one-chat-locked
    shoot "$mode" member mentions 4-mentions
    shoot "$mode" member me       5a-me
    shoot "$mode" guest  me       5b-me-signed-out
done
xcrun simctl keychain "$dev" reset
echo "screenshots: $out"
