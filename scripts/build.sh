#!/usr/bin/env bash
# Build and test for the iOS Simulator, arm64 only (the Matrix SDK ships no x86_64
# simulator slice). Signing is ad hoc, which the simulator accepts.
#
#   scripts/build.sh build              build the app
#   scripts/build.sh build-for-testing  build the app and every test bundle once, for CI's shards
#   scripts/build.sh test               build and run the unit tests
#   scripts/build.sh ui                 run the UI tests (blog → discussion → swipe back)
#   scripts/build.sh integration        run the sign-in test against a test homeserver
#                                       (needs IPHONEBLOG_TEST_* in the environment,
#                                       see scripts/test-homeserver.sh)
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
# Lowest CPU priority on Thorsten's Mac (scripts/low-priority.sh).
. scripts/low-priority.sh
mkdir -p build
action="${1:-build}"

# An iPhone 17 Pro on the newest iOS runtime, created when the machine has none; DEVICE=<udid>
# picks another (the 393 pt screenshots for design pages). Never "the first iPhone": the
# iOS 27.2 runtime's default set holds only the iPhone Duo, a foldable whose inner screen gets
# the iPad layout without a tab bar, and every tab test failed on it (docs/mac-runner.md).
# DEVICE_NAME gives each Mac runner instance its own simulator (its .env sets it).
device_type="${DEVICE_TYPE:-iPhone 17 Pro}"
device_name="${DEVICE_NAME:-$device_type}"
device="${DEVICE:-}"
if [[ -z "$device" && "$action" != build && "$action" != build-for-testing ]]; then
    read -r runtime device < <(xcrun simctl list -j devices available runtimes | DEVICE_TYPE="$device_name" python3 -c '
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
        device="$(xcrun simctl create "$device_name" "$device_type" "$runtime")"
        echo "build.sh: created $device_name ($device_type) on $runtime ($device)" >&2
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
    lower_start "$device"
    lowprio xcodebuild "$@" 2>&1 | tee "$log" | grep -E 'error:|Test Case .*(passed|failed|skipped)|\*\* (BUILD|TEST) '
    local status=${PIPESTATUS[0]}
    lower_stop
    set -e
    return "$status"
}

# The app's own settings live in its data container (no simctl command reaches them). On a
# booted simulator a failed lookup means the app is not installed, so there is nothing to clear.
clear_app_settings() {
    local data
    data="$(xcrun simctl get_app_container "$device" de.iphoneblog.matrix.preview data 2>/dev/null)" || return 0
    rm -f "${data:?}/Library/Preferences/de.iphoneblog.matrix.preview.plist"
}

# A simulator without the last run's state. A session from an earlier test server survives in
# its keychain, even an uninstall, and its token is dead on a fresh server; and every fresh test
# server has the same @tester, whose "Neue Artikel" rule the app would remember as seeded.
# Both commands fail on a shut-down simulator ("Unable to lookup in current state: Shutdown"),
# which hid the leftovers on machines that keep their simulators (the Mac Studio runner, a
# laptop): boot first, and stop if the reset fails.
# In CI (CI=true) the simulator is erased instead: the Mac Studio keeps its simulators, and their
# photo library grew by two pictures every run until the photo picker's UI query timed out
# (RichMessagesUITests, 2026-11-21); GitHub's runners start with an empty one.
fresh_simulator() {
    if [[ "${CI:-}" == true ]]; then
        xcrun simctl shutdown "$device" 2>/dev/null || true
        xcrun simctl erase "$device"
    fi
    xcrun simctl bootstatus "$device" -b >/dev/null
    xcrun simctl keychain "$device" reset
    clear_app_settings
}

# How a test action reaches its tests: by building the scheme, or, with TEST_WITHOUT_BUILDING=1
# (CI's shards), from the products build-for-testing left in build/DerivedData.
test_args() { # scheme: where the tests come from
    if [[ "${TEST_WITHOUT_BUILDING:-}" == 1 ]]; then
        local xctestrun
        xctestrun="$(ls build/DerivedData/Build/Products/"$1"_*.xctestrun 2>/dev/null | head -1)"
        [[ -n "$xctestrun" ]] || { echo "build.sh: no $1 xctestrun; run build-for-testing first" >&2; exit 1; }
        echo -xctestrun "$xctestrun" -destination "id=$device"
    else
        echo "${common[@]}" -scheme "$1" -destination "id=$device"
    fi
}
test_verb() { if [[ "${TEST_WITHOUT_BUILDING:-}" == 1 ]]; then echo test-without-building; else echo test; fi; }

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
    build-for-testing)
        for scheme in iphoneblog Integration UITests; do
            run "build-for-testing-$scheme" "${common[@]}" -scheme "$scheme" \
                -destination 'generic/platform=iOS Simulator' build-for-testing
        done
        ;;
    enumerate-ui)
        # Every UI test the built products hold, for scripts/ui-shards.py.
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        TEST_WITHOUT_BUILDING=1
        # shellcheck disable=SC2046
        xcodebuild $(test_args UITests) test-without-building -enumerate-tests -test-enumeration-format json \
            -test-enumeration-style flat -test-enumeration-output-path build/ui-tests.json >build/enumerate.log 2>&1 \
            || { tail -20 build/enumerate.log >&2; exit 1; }
        ;;
    build)
        run build "${common[@]}" -scheme iphoneblog -destination 'generic/platform=iOS Simulator' build
        ;;
    test)
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        # shellcheck disable=SC2046
        run test $(test_args iphoneblog) "$(test_verb)"
        ;;
    integration)
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        fresh_simulator
        # xcodebuild hands TEST_RUNNER_<NAME> to the test process as <NAME>.
        export TEST_RUNNER_IPHONEBLOG_TEST_HOMESERVER="${IPHONEBLOG_TEST_HOMESERVER:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_USER="${IPHONEBLOG_TEST_USER:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_PASSWORD="${IPHONEBLOG_TEST_PASSWORD:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_ROOMS="${IPHONEBLOG_TEST_ROOMS:-}"
        export TEST_RUNNER_IPHONEBLOG_TEST_MENTION_ROOM="${IPHONEBLOG_TEST_MENTION_ROOM:-}"
        export TEST_RUNNER_IPHONEBLOG_ONE_ALIAS="${IPHONEBLOG_ONE_ALIAS:-}"
        export TEST_RUNNER_IPHONEBLOG_BLOG_ALIAS="${IPHONEBLOG_BLOG_ALIAS:-}"
        export TEST_RUNNER_IPHONEBLOG_CHANNEL_ALIAS="${IPHONEBLOG_CHANNEL_ALIAS:-}"
        # shellcheck disable=SC2046
        run integration $(test_args Integration) "$(test_verb)"
        ;;
    ui)
        # The reader's way from the blog into a discussion and back. Starts the blog fixture;
        # the member test also runs when IPHONEBLOG_TEST_* name a test homeserver.
        [[ -n "$device" ]] || { echo "build.sh: no iPhone simulator" >&2; exit 1; }
        # Booted, too, because addmedia fails without a word on a shut-down simulator.
        fresh_simulator
        # An animated GIF in the photo library, for the test that sends one (GifUITests).
        add_photo scripts/fixtures/animation.gif
        # A photo dated 2001-01-01, so the picker labels it with "2001" and the Markup test finds
        # it among the GIFs other tests add (RichMessagesUITests.testPhotoMarkupIsSent).
        add_photo scripts/fixtures/markup-photo.jpg
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
        # UI_ONLY=RichMessagesUITests (or Class/test) runs a part; UI_TESTS_FILE names a file with
        # one UITests/Class/test per line (a CI shard, scripts/ui-shards.py).
        only=()
        [[ -n "${UI_ONLY:-}" ]] && only+=(-only-testing:"UITests/$UI_ONLY")
        if [[ -n "${UI_TESTS_FILE:-}" ]]; then
            while read -r t; do [[ -n "$t" ]] && only+=(-only-testing:"$t"); done < "$UI_TESTS_FILE"
            (( ${#only[@]} > 0 )) || { echo "build.sh: $UI_TESTS_FILE is empty" >&2; exit 1; }
        fi
        # A failed test runs once more: on CI's slow runners the simulator now and then fails to
        # launch the app at all ("does not have a process ID").
        # shellcheck disable=SC2046
        run ui $(test_args UITests) -resultBundlePath build/ui.xcresult \
            -retry-tests-on-failure -test-iterations 2 ${only[@]+"${only[@]}"} "$(test_verb)"
        ;;
    *)
        echo "usage: scripts/build.sh build|test|integration|ui" >&2; exit 2 ;;
esac
