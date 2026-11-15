#!/usr/bin/env bash
# Build and test for the iOS Simulator, arm64 only (the Matrix SDK ships no x86_64
# simulator slice). Signing is ad hoc, which the simulator accepts.
#
#   scripts/build.sh build              build the app
#   scripts/build.sh test               build and run the unit tests
#   scripts/build.sh integration        run the sign-in test against a test homeserver
#                                       (needs IPHONEBLOG_TEST_* in the environment,
#                                       see scripts/test-homeserver.sh)
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
mkdir -p build
action="${1:-build}"

# The newest available iPhone simulator, by runtime version.
device="$(xcrun simctl list devices available -j | python3 -c '
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
        # xcodebuild hands TEST_RUNNER_<NAME> to the test process as <NAME>.
        export TEST_RUNNER_IPHONEBLOG_TEST_HOMESERVER="${IPHONEBLOG_TEST_HOMESERVER:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_USER="${IPHONEBLOG_TEST_USER:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_PASSWORD="${IPHONEBLOG_TEST_PASSWORD:?}"
        export TEST_RUNNER_IPHONEBLOG_TEST_ROOMS="${IPHONEBLOG_TEST_ROOMS:-}"
        export TEST_RUNNER_IPHONEBLOG_TEST_MENTION_ROOM="${IPHONEBLOG_TEST_MENTION_ROOM:-}"
        export TEST_RUNNER_IPHONEBLOG_ONE_ALIAS="${IPHONEBLOG_ONE_ALIAS:-}"
        export TEST_RUNNER_IPHONEBLOG_BLOG_ALIAS="${IPHONEBLOG_BLOG_ALIAS:-}"
        export TEST_RUNNER_IPHONEBLOG_TEST_ARTICLE_TITLE="${IPHONEBLOG_TEST_ARTICLE_TITLE:-}"
        run integration "${common[@]}" -scheme Integration -destination "id=$device" test
        ;;
    *)
        echo "usage: scripts/build.sh build|test|integration" >&2; exit 2 ;;
esac
