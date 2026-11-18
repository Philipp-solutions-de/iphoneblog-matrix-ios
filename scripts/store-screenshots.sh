#!/usr/bin/env bash
# The App Store screenshots: six shots on a 6.9" iPhone, German, light, articles first
# (docs/app-store.md, "Store listing"). Written to fastlane/screenshots/de-DE, where
# `fastlane ios store_listing` uploads them.
#
#   scripts/store-screenshots.sh <simulator-udid> <blog-api-url> <blog-web-url> <article-url>
#
# <simulator-udid>  an iPhone 17 Pro Max (1320 x 2868, Apple's 6.9" size)
# <blog-api-url>    serves threads.json, threads/ and links.json, e.g.
#                   https://chat.iphoneblog.de/_iphoneblog/v1/blog
# <blog-web-url>    the blog's app view, e.g. https://www.iphoneblog.de/?app=1
# <article-url>     one public article in the app view, e.g. https://www.iphoneblog.de/<path>/?app=1
#
# The signed-in shots use the test server (scripts/test-homeserver.sh start), whose env file is
# build/test-homeserver.env, or the one HOMESERVER_ENV names. Build the app first
# (scripts/build.sh build). The status bar shows 9:41, full battery and Wi-Fi, as Apple's own.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dev="$1"; api="$2"; web="$3"; article="$4"
out="$here/fastlane/screenshots/de-DE"
app="$here/build/DerivedData/Build/Products/Debug-iphonesimulator/iphoneblog.app"
id="$(sed -n 's/^BUNDLE_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$here/brand.env")"
mkdir -p "$out"
rm -f "$out"/*.png

xcrun simctl boot "$dev" 2>/dev/null || true
xcrun simctl bootstatus "$dev" -b >/dev/null
xcrun simctl ui "$dev" appearance light
xcrun simctl status_bar "$dev" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
# A fresh install: no settings left from a test run on the same simulator.
xcrun simctl uninstall "$dev" "$id" 2>/dev/null || true
xcrun simctl install "$dev" "$app"
set -a; . "${HOMESERVER_ENV:-$here/build/test-homeserver.env}"; set +a

shoot() { # who tab name [VAR=value ...]
    local who="$1" tab="$2" name="$3"; shift 3
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
    local blog="$web"
    for pair in "$@"; do
        case "$pair" in
            BLOG_WEB=*) blog="${pair#BLOG_WEB=}" ;;
            *) extra+=("SIMCTL_CHILD_$pair") ;;
        esac
    done
    env ${extra[@]+"${extra[@]}"} SIMCTL_CHILD_IPHONEBLOG_BLOG_API="$api" SIMCTL_CHILD_IPHONEBLOG_BLOG_WEB="$blog" \
        SIMCTL_CHILD_IPHONEBLOG_START_TAB="$tab" SIMCTL_CHILD_IPHONEBLOG_NO_PUSH_PROMPT=1 \
        SIMCTL_CHILD_AppleLanguages="(de)" SIMCTL_CHILD_AppleLocale=de_DE \
        xcrun simctl launch "$dev" "$id" -AppleLanguages "(de)" -AppleLocale de_DE >/dev/null
    sleep 16
    xcrun simctl io "$dev" screenshot "$out/$name.png" >/dev/null 2>&1
}

shoot guest  blog 1_artikel
shoot guest  blog 2_artikel-offen "BLOG_WEB=$article"
shoot member blog 3_diskussion "IPHONEBLOG_START_DISCUSSION=$IPHONEBLOG_TEST_ARTICLE_ROOT"
shoot member chat 4_one
shoot member chat 5_thread "IPHONEBLOG_START_THREAD=$IPHONEBLOG_TEST_CHANNEL_ROOM|$IPHONEBLOG_TEST_CHANNEL_THREAD"
shoot member me   6_ich

xcrun simctl keychain "$dev" reset
xcrun simctl status_bar "$dev" clear
echo "store screenshots: $out"
