#!/usr/bin/env bash
# Shut down this runner instance's simulator at the end of a job on a self-hosted Mac, so no
# simulator idles between jobs (docs/mac-runner.md, "Priority"). Only its own: four shards run
# side by side under the same user, each with the device its .env names (DEVICE_NAME).
set -euo pipefail
name="${DEVICE_NAME:-${DEVICE_TYPE:-iPhone 17 Pro}}"
xcrun simctl list -j devices | NAME="$name" python3 -c '
import json, os, sys
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == os.environ["NAME"] and d["state"] != "Shutdown":
            print(d["udid"])
' | while read -r udid; do
    xcrun simctl shutdown "$udid" && echo "shut down $name ($udid)"
done
