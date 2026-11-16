#!/usr/bin/env bash
# The performance tests (docs/performance.md): a throwaway Synapse with a seeded history, the
# blog fixture, the PerfTests scheme in the Perf configuration on an iPhone Pro simulator, and
# the gate that compares the numbers with scripts/perf-baseline.json.
#
#   scripts/perf.sh               build, run, gate
#   scripts/perf.sh run           run and gate without building again
#   scripts/perf.sh gate          gate the last result (build/perf.xcresult)
#   scripts/perf.sh baseline      run, then write the medians into scripts/perf-baseline.json
#   PERF_ONLY=testScrollOneChat scripts/perf.sh run     one test
#   PERF_DEVICE_UDID=<udid> scripts/perf.sh device      build for and run on a real device,
#                                                       signed with APPLE_TEAM_ID (brand.env)
#
# **Its own ports and folders** (8048, 8796, build/perf-synapse), so it runs beside the other
# test servers on a shared Mac. The homeserver is scripts/test-homeserver.sh's, copied to
# build/ with those three things changed, so both start the same server.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
mkdir -p build
action="${1:-all}"
port="${PERF_HOMESERVER_PORT:-8048}"
fixture_port="${PERF_FIXTURE_PORT:-8796}"
result=build/perf.xcresult

# **Its own simulator**, "perf-iphone-pro": the newest "iPhone NN Pro" device type on the
# newest iOS runtime, made on first use. Its keychain is reset before every run, which must
# never happen to a simulator somebody else uses. PERF_DEVICE (a UDID) overrides it.
device="${PERF_DEVICE:-$(xcrun simctl list -j | python3 -c '
import json, re, subprocess, sys
data = json.load(sys.stdin)
for runtime, devices in data["devices"].items():
    for d in devices:
        if d["name"] == "perf-iphone-pro" and d["isAvailable"]:
            print(d["udid"]); sys.exit()
runtimes = [r for r in data["runtimes"] if r["isAvailable"] and r.get("platform", "iOS") == "iOS"
            and r["name"].startswith("iOS")]
runtimes.sort(key=lambda r: [int(x) for x in re.findall(r"\d+", r["version"])], reverse=True)
number = lambda t: int(re.search(r"\d+", t["name"]).group())
# The newest runtime with an "iPhone NN Pro"; failing that, the newest numbered iPhone. A runtime
# may list no supported types (a CI image), so fall back to every type Xcode knows.
for pattern in (r"iPhone \d+ Pro", r"iPhone \d+( Pro)?( Max)?"):
    found = [(r, t) for r in runtimes for t in (r.get("supportedDeviceTypes") or data["devicetypes"])
             if re.fullmatch(pattern, t["name"])]
    if found:
        break
else:
    sys.exit("perf.sh: no iPhone simulator type; runtimes: %s; types: %s" % (
        [r["name"] for r in runtimes], [t["name"] for t in data["devicetypes"]][:40]))
# Newest runtime first, newest model first; a type the runtime cannot run is refused by simctl.
found.sort(key=lambda rt: ([int(x) for x in re.findall(r"\d+", rt[0]["version"])], number(rt[1])), reverse=True)
errors = []
for runtime, kind in found:
    out = subprocess.run(["xcrun", "simctl", "create", "perf-iphone-pro", kind["identifier"], runtime["identifier"]],
                         capture_output=True, text=True)
    if out.returncode == 0:
        print(out.stdout.strip()); sys.exit()
    errors.append("%s on %s: %s" % (kind["name"], runtime["name"], out.stderr.strip()[:120]))
sys.exit("perf.sh: no simulator could be made:\n" + "\n".join(errors[:8]))
')}"
[[ -n "$device" ]] || { echo "perf.sh: no iPhone Pro simulator" >&2; exit 1; }

# **A real device** (docs/performance.md, "On a device"): signed with the team, no simulator
# flags, and the servers reached over the Mac's LAN address through scripts/lan-forward.py.
if [[ -n "${PERF_DEVICE_UDID:-}" ]]; then
    device="$PERF_DEVICE_UDID"
    team="${APPLE_TEAM_ID:?set APPLE_TEAM_ID, the team that signs for the device}"
    lan="${PERF_LAN_ADDRESS:-$(ipconfig getifaddr en0 || ipconfig getifaddr en1)}"
    # A device not yet in the team is registered on the first build: the team holder's
    # decision, taken once (Thorsten, 2026-11-16, for the iPad Pro).
    signing=(DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -allowProvisioningDeviceRegistration)
else
    lan=""
    signing=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

common=(
    -project iphoneblog.xcodeproj
    -scheme PerfTests
    -configuration Perf
    -derivedDataPath build/DerivedData
    -destination "id=$device"
    -skipPackagePluginValidation
    -skipMacroValidation
    "${signing[@]}"
    COMPILER_INDEX_STORE_ENABLE=NO
)

build() {
    xcodebuild "${common[@]}" build-for-testing 2>&1 | tee build/perf-build.log \
        | grep -E 'error:|\*\* (BUILD|TEST) ' || true
    grep -q '\*\* TEST BUILD SUCCEEDED \*\*' build/perf-build.log
}

start_servers() {
    for p in "$port" "$fixture_port"; do
        if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
            echo "perf.sh: port $p is taken; set PERF_HOMESERVER_PORT / PERF_FIXTURE_PORT" >&2; exit 1
        fi
    done
    PERF_PORT="$port" python3 - <<'PY'
import os
port = os.environ["PERF_PORT"]
s = open("scripts/test-homeserver.sh").read()
bind = "sed -i.bak 's/bind_addresses"
assert "127.0.0.1:8008" in s and "/build/synapse" in s and bind in s, "test-homeserver.sh changed shape"
s = (s.replace("127.0.0.1:8008", f"127.0.0.1:{port}")
      .replace("/build/synapse", "/build/perf-synapse")
      .replace("build/test-homeserver.env", "build/perf-homeserver.env")
      .replace(bind, f"sed -i.bak 's/port: 8008/port: {port}/' homeserver.yaml\n" + bind, 1))
open("build/perf-homeserver.sh", "w").write(s)
PY
    chmod +x build/perf-homeserver.sh
    build/perf-homeserver.sh start
    python3 scripts/seed-perf-data.py
    set -a; . build/perf-homeserver.env; . build/perf-data.env; set +a
    python3 scripts/blog-fixture-server.py "$fixture_port" "$IPHONEBLOG_TEST_ARTICLE_ROOT" >build/perf-fixture.log 2>&1 &
    echo $! > build/perf-fixture.pid
    sleep 1
    if [[ -n "$lan" ]]; then
        /usr/bin/python3 scripts/lan-forward.py "$lan" "$port" "$fixture_port" >build/perf-forward.log 2>&1 &
        echo $! > build/perf-forward.pid
        sleep 1
    fi
}

stop_servers() {
    [[ -f build/perf-forward.pid ]] && kill "$(cat build/perf-forward.pid)" 2>/dev/null || true
    [[ -f build/perf-fixture.pid ]] && kill "$(cat build/perf-fixture.pid)" 2>/dev/null || true
    [[ -x build/perf-homeserver.sh ]] && build/perf-homeserver.sh stop || true
}

run() {
    trap stop_servers EXIT
    start_servers
    export TEST_RUNNER_IPHONEBLOG_FIXTURE="http://${lan:-127.0.0.1}:$fixture_port"
    # Where the app writes its frame totals and the tests read them (HitchMetric).
    export TEST_RUNNER_IPHONEBLOG_PERF_STATS="$here/build/perf-stats.json"
    for name in TEST_HOMESERVER TEST_USER TEST_PASSWORD ONE_ALIAS BLOG_ALIAS CHANNEL_ALIAS PERF_THREAD_SENDER; do
        var="IPHONEBLOG_$name"
        [[ -n "${!var:-}" ]] && export "TEST_RUNNER_$var=${!var}"
    done
    [[ -n "$lan" ]] && export TEST_RUNNER_IPHONEBLOG_TEST_HOMESERVER="http://$lan:$port"
    if [[ -n "$lan" ]]; then
        # A device keeps its keychain across a reinstall too; testLaunch runs first and signs
        # out, which deletes the stored session before the signed-in tests start.
        unset TEST_RUNNER_IPHONEBLOG_PERF_STATS
    else
    # **A clean app every run.** The session the last run left in the simulator's keychain names
    # a server this run rebuilt, and the app signs in by itself only when nothing is stored.
    bundle_id="$(. ./brand.env; echo "$BUNDLE_ID")"
    xcrun simctl boot "$device" 2>/dev/null || true
    xcrun simctl uninstall "$device" "$bundle_id" 2>/dev/null || true
    # The keychain outlives the app; without this the app restores a token of the last run's
    # server, is refused with 401, and shows #one-Chat locked.
    if [[ -z "${PERF_DEVICE:-}" ]]; then xcrun simctl keychain "$device" reset; fi
    fi
    only=()
    [[ -n "${PERF_ONLY:-}" ]] && only=(-only-testing "PerfTests/PerformanceTests/$PERF_ONLY")
    rm -rf "$result"
    set +e
    xcodebuild "${common[@]}" -resultBundlePath "$result" ${only[@]+"${only[@]}"} test-without-building 2>&1 \
        | tee build/perf.log | grep -E 'error:|Test Case .*(passed|failed|skipped)|measured \[|\*\* TEST '
    set -e
}

case "$action" in
    all)      build; run; python3 scripts/perf-gate.py "$result" ;;
    device)   [[ -n "${PERF_DEVICE_UDID:-}" ]] || { echo "perf.sh: set PERF_DEVICE_UDID" >&2; exit 2; }
              build; run ;;
    build)    build ;;
    run)      run; python3 scripts/perf-gate.py "$result" ;;
    gate)     python3 scripts/perf-gate.py "$result" ;;
    baseline) run; python3 scripts/perf-gate.py "$result" --write-baseline ;;
    *) echo "usage: scripts/perf.sh [all|build|run|gate|baseline]" >&2; exit 2 ;;
esac
