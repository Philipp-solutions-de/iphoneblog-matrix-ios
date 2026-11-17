#!/usr/bin/env bash
# Fails when an App Store build carries the simulator-only test-gate path (BlogTab.swift,
# testGateCookie): its marker strings must not be anywhere in the app. Fails too when the
# TestFlight-only gate for speed reports (MetricsReporter, "rum-gate-v1") is missing. fastlane's beta lane
# runs this between archive and upload.
#   scripts/check-release-clean.sh <path to .ipa or .app>
set -euo pipefail
target="${1:?usage: check-release-clean.sh <ipa|app>}"
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
if [[ "$target" == *.ipa ]]; then
    unzip -q "$target" -d "$work"
    app="$(find "$work/Payload" -maxdepth 1 -name '*.app' | head -1)"
else
    app="$target"
fi
# Every file in the bundle: a Debug build keeps the app's code in iphoneblog.debug.dylib, and
# frameworks carry their own binaries.
found=0
for marker in SIMULATOR_HOST_HOME test-gate-beta test_gate; do
    if hits="$(grep -r -a -l "$marker" "$app")"; then
        echo "check-release-clean: '$marker' found in: ${hits//$app\//}; the test-gate path must not ship" >&2
        found=1
    fi
done
# The speed reports may only leave TestFlight builds (GDPR): the gate in MetricsReporter must be
# compiled in, or an App Store copy of this binary would report.
if ! grep -r -a -q "rum-gate-v1" "$app"; then
    echo "check-release-clean: the TestFlight-only gate for speed reports (rum-gate-v1) is missing" >&2
    found=1
fi
[[ $found == 0 ]] && echo "check-release-clean: no test-gate path, speed-report gate present in $(basename "$app")"
exit $found
