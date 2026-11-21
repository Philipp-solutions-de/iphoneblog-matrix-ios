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

# An iPhone 17 Pro on the newest iOS runtime, created when the machine has none; DEVICE=<udid>
# picks another (the 393 pt screenshots for design pages). Never "the first iPhone": the
# iOS 27.2 runtime's default set holds only the iPhone Duo, a foldable whose inner screen gets
# the iPad layout without a tab bar, and every tab test failed on it (docs/mac-runner.md).
device_type="${DEVICE_TYPE:-iPhone 17 Pro}"
device="${DEVICE:-}"
if [[ -z "$device" ]]; then
    read -r runtime device < <(xcrun simctl list -j devices available runtimes | DEVICE_TYPE="$device_type" python3 -c '
import json, os, re, sys
data = json.load(sys.stdin)
want = os.environ["DEVICE_TYPE"]
runtimes = [r for r in data["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
# The general runtime before a device-specific one of the same version (iOS-27-2-iPhone19-4
# runs only the Duo).
runtimes.sort(key=lambda r: (tuple(int(x) for x in r["version"].split(".")),
                             re.search(r"iOS-\d+(-\d+)*$", r["identifier"]) is not None))
if not runtimes:
    sys.exit(1)
newest = runtimes[-1]["identifier"]
match = [d["udid"] for d in data["devices"].get(newest, []) if d["name"] == want]
print(newest, match[0] if match else "")
') || true
    if [[ -z "$device" && -n "${runtime:-}" ]]; then
        device="$(xcrun simctl create "$device_type" "$device_type" "$runtime")"
        echo "build.sh: created $device_type on $runtime ($device)" >&2
    fi
fi

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
        xcrun simctl addmedia "$device" scripts/fixtures/animation.gif
        # A photo dated 2001-01-01, so the picker labels it with "2001" and the Markup test finds
        # it among the GIFs other tests add (RichMessagesUITests.testPhotoMarkupIsSent).
        xcrun simctl addmedia "$device" scripts/fixtures/markup-photo.jpg
        clear_app_settings
        fixture_port="${FIXTURE_PORT:-8793}" # another port beside a running one (docs/mac-runner.md)
        if curl -s -o /dev/null "http://127.0.0.1:$fixture_port/calls"; then
            echo "build.sh: port $fixture_port is taken; stop the old fixture server first" >&2; exit 1
        fi
        python3 scripts/blog-fixture-server.py "$fixture_port" "${IPHONEBLOG_TEST_ARTICLE_ROOT:-\$madebypost}" &
        fixture=$!
        trap 'kill "$fixture" 2>/dev/null' EXIT
        sleep 1
        export TEST_RUNNER_IPHONEBLOG_FIXTURE="http://127.0.0.1:$fixture_port"
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
