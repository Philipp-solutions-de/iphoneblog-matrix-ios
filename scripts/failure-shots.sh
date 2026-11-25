#!/bin/bash
# Exports every attachment (the tests' own `save` screenshots included) of each failed test
# in a result bundle, under readable names: <test>/<attachment name>.png.
# `xcresulttool export attachments --only-failures` is not enough: it takes only what XCTest
# itself ties to a failure, and our tests attach their screenshots themselves.
# Usage: scripts/failure-shots.sh <bundle.xcresult> <output dir>
set -euo pipefail

bundle="$1" out="$2"
[[ -d "$bundle" ]] || { echo "no result bundle at $bundle"; exit 0; }

failed="$(xcrun xcresulttool get test-results tests --path "$bundle" | python3 -I -c '
import json, sys
def walk(node):
    if node.get("nodeType") == "Test Case" and node.get("result") != "Passed":
        print(node["nodeIdentifierURL"])
    for child in node.get("children", []):
        walk(child)
for node in json.load(sys.stdin).get("testNodes", []):
    walk(node)
')"
[[ -n "$failed" ]] || { echo "no failed test in $bundle"; exit 0; }

while IFS= read -r id; do
    name="${id##*/}"
    dir="$out/$name"
    raw="$out/.raw-$name"
    rm -rf "$raw"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" --test-id "$id" >/dev/null \
        || { echo "could not export $id"; continue; }
    mkdir -p "$dir"
    python3 -I - "$raw" "$dir" <<'PY'
import json, os, shutil, sys
raw, dest = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
        name = f'try{a.get("repetitionNumber", 1)}-{name}'.replace("/", "_")
        shutil.copy(os.path.join(raw, a["exportedFileName"]), os.path.join(dest, name))
PY
    rm -rf "$raw"
    echo "$name: $(ls "$dir" | wc -l | tr -d ' ') attachments"
done <<< "$failed"
