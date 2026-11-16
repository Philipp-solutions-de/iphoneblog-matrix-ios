#!/usr/bin/env bash
# Fails when an App Store build carries the simulator-only test-gate path (BlogTab.swift,
# testGateCookie): its marker strings must not be anywhere in the app. fastlane's beta lane
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
[[ $found == 0 ]] && echo "check-release-clean: no test-gate path in $(basename "$app")"
exit $found
