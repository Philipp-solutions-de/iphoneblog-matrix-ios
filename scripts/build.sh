#!/usr/bin/env bash
# Build and test for the iOS Simulator, arm64 only (the Matrix SDK ships no x86_64
# simulator slice). Signing is ad hoc, which the simulator accepts.
#
#   scripts/build.sh build              build the app
#   scripts/build.sh test               build and run the unit tests
#   scripts/build.sh ui                 run the UI tests (blog → discussion → swipe back)
#   scripts/build.sh integration        run the sign-in test against a test homeserver
#                                       (needs IPHONEBLOG_TEST_* in the environment,
#                                       see scripts/test-homeserver.sh)
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
mkdir -p build
action="${1:-build}"

# The newest available iPhone simulator, by runtime version; DEVICE=<udid> picks one (the
# 393 pt screenshots for design pages).
device="${DEVICE:-}"
[[ -n "$device" ]] || device="$(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d["name"].startswith("iPhone") and (best is None or version > best[0]):
            best = (version, d["udid"], d["name"])
print(best[1] if best else "")
')"

common=(
    -project iphoneblog.xcodeproj
    -derivedDataPath build/DerivedData
    -skipPackagePluginValidation
    -skipMacroValidation
    ARCHS=arm64
    ONLY_ACTIVE_ARCH=YES
    CODE_SIGN_IDENTITY=-
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=
    COMPILER_INDEX_STORE_ENABLE=NO
)

run() {
    local log="build/$1.log"; shift
    set +e
    xcodebuild "$@" 2>&1 | tee "$log" | grep -E 'error:|Test Case .*(passed|failed|skipped)|\*\* (BUILD|TEST) '
    local status=${PIPESTATUS[0]}
    set -e
    return "$status"
}

# The app's own settings live in its data container (no simctl command reaches them).
clear_app_settings() {
    local data
    data="$(xcrun simctl get_app_container "$device" de.iphoneblog.matrix.preview data 2>/dev/null)" || return 0
    rm -f "${data:?}/Library/Preferences/de.iphoneblog.matrix.preview.plist"
}

# A picture in the simulator's photo library, imported until the library shows it. addmedia
# right after a boot, or on a freshly erased simulator, can return before the library is ready
# and the import is lost without a word: the picker then shows no pictures (2026-11-21, CI).
add_photo() {
    local file="$1" library before tries
    library="$HOME/Library/Developer/CoreSimulator/Devices/$device/data/Media/PhotoData/Photos.sqlite"
    photo_count() { sqlite3 -readonly "$library" "SELECT count(*) FROM ZASSET WHERE ZTRASHEDSTATE = 0" 2>/dev/null || echo 0; }
    before="$(photo_count)"
    for tries in 1 2 3; do
        xcrun simctl addmedia "$device" "$file"
        for _ in $(seq 1 30); do
            [[ "$(photo_count)" -gt "$before" ]] && return 0
            sleep 1
        done
        echo "build.sh: $file is not in the photo library after 30 s (import $tries of 3)" >&2
    done
    # No library where CoreSimulator keeps it: nothing to check, the tests will tell.
    [[ -f "$library" ]] || { echo "build.sh: no photo library at $library, import unchecked" >&2; return 0; }
    echo "build.sh: $file never reached the photo library" >&2
    return 1
}

case "$action" in
    build)
        run build "${common[@]}" -scheme iphoneblog -destination 'generic/platform=iOS Simulator' build
        ;;
    test)
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        run test "${common[@]}" -scheme iphoneblog -destination "id=$device" test
        ;;
    integration)
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        # A session from an earlier test server survives in the simulator's keychain, even an
        # uninstall, and its token is dead on a fresh server.
        xcrun simctl keychain "$device" reset 2>/dev/null || true
        # And the app's settings: every fresh test server has the same @tester, whose "Neue
        # Artikel" rule the app would remember as seeded.
        clear_app_settings
        # xcodebuild hands TEST_RUNNER_<NAME> to the test process as <NAME>.
        export TEST_RUNNER_IPHONEBLOG_TEST_HOMESERVER="${IPHONEBLOG_TEST_HOMESERVER:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_USER="${IPHONEBLOG_TEST_USER:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_PASSWORD="${IPHONEBLOG_TEST_PASSWORD:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_ROOMS="${IPHONEBLOG_TEST_ROOMS:-}"
        export TEST_RUNNER_IPHONEBLOG_TEST_MENTION_ROOM="${IPHONEBLOG_TEST_MENTION_ROOM:-}"
        export TEST_RUNNER_IPHONEBLOG_ONE_ALIAS="${IPHONEBLOG_ONE_ALIAS:-}"
        export TEST_RUNNER_IPHONEBLOG_BLOG_ALIAS="${IPHONEBLOG_BLOG_ALIAS:-}"
        export TEST_RUNNER_IPHONEBLOG_CHANNEL_ALIAS="${IPHONEBLOG_CHANNEL_ALIAS:-}"
        run integration "${common[@]}" -scheme Integration -destination "id=$device" test
        ;;
    ui)
        # The reader's way from the blog into a discussion and back. Starts the blog fixture;
        # the member test also runs when IPHONEBLOG_TEST_* name a test homeserver.
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        xcrun simctl keychain "$device" reset 2>/dev/null || true # as for integration
        # addmedia needs a booted simulator, and xcodebuild boots it only later: on a shut-down
        # one every import failed without a word (2026-11-20).
        xcrun simctl bootstatus "$device" -b >/dev/null
        # An animated GIF in the photo library, for the test that sends one (GifUITests).
        add_photo scripts/fixtures/animation.gif
        # A photo dated 2001-01-01, so the picker labels it with "2001" and the Markup test finds
        # it among the GIFs other tests add (RichMessagesUITests.testPhotoMarkupIsSent).
        add_photo scripts/fixtures/markup-photo.jpg
        clear_app_settings
        if curl -s -o /dev/null http://127.0.0.1:8793/calls; then
            echo "build.sh: port 8793 is taken; stop the old fixture server first" >&2; exit 1
        fi
        python3 scripts/blog-fixture-server.py 8793 "${IPHONEBLOG_TEST_ARTICLE_ROOT:-\$madebypost}" &
        fixture=$!
        trap 'kill "$fixture" 2>/dev/null' EXIT
        sleep 1
        export TEST_RUNNER_IPHONEBLOG_FIXTURE="http://127.0.0.1:8793"
        for name in TEST_HOMESERVER TEST_USER TEST_PASSWORD TEST_USER2 TEST_PASSWORD2 TEST_USER3 TEST_PASSWORD3 TEST_ADMIN TEST_ADMIN_PASSWORD ONE_ALIAS BLOG_ALIAS CHANNEL_ALIAS TEST_CHANNEL_ROOM TEST_ROOM2 TEST_BLOG_ROOM TEST_CHANNEL_THREAD TEST_ARTICLE_ROOT TEST_SYNAPSE_LOG; do
            var="IPHONEBLOG_$name"
            [[ -n "${!var:-}" ]] && export "TEST_RUNNER_$var=${!var}"
        done
        rm -rf build/ui.xcresult
        # UI_ONLY=RichMessagesUITests (or Class/test) runs a part.
        # A failed test runs once more: on CI's slow runners the simulator now and then fails to
        # launch the app at all ("does not have a process ID").
        run ui "${common[@]}" -scheme UITests -destination "id=$device" -resultBundlePath build/ui.xcresult \
            -retry-tests-on-failure -test-iterations 2 \
            ${UI_ONLY:+-only-testing:"UITests/$UI_ONLY"} test
        ;;
    *)
        echo "usage: scripts/build.sh build|test|integration|ui" >&2; exit 2 ;;
esac
