#!/usr/bin/env bash
# Fail when a prepared tree still carries Element's marks where a user sees them.
#   scripts/check-marks.sh <prepared-tree>
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
tree="$1"
bad=0

same() { cmp -s "$1" "$2" || { echo "check-marks: $2 is not ours" >&2; bad=1; }; }

same "$here/overlay/ElementX/Resources/AppIcon.icon/Assets/AppIcon.png" "$tree/ElementX/Resources/AppIcon.icon/Assets/AppIcon.png"
for f in "$here"/overlay/ElementX/Resources/Assets.xcassets/images/*.imageset/*; do
    same "$f" "$tree/${f#"$here/overlay/"}"
done

if grep -q 'Element' <(grep -E '^\s+(APP_DISPLAY_NAME|PRODUCTION_APP_NAME):' "$tree/app.yml"); then
    echo "check-marks: app.yml still names Element" >&2; bad=1
fi
if grep -qE '(applinks|webcredentials):.*element\.io' "$tree/ElementX/SupportingFiles/target.yml"; then
    echo "check-marks: target.yml still claims an element.io domain" >&2; bad=1
fi
if grep -qE '"https?://[^"]+"' "$tree/Components/Secrets/Secrets.swift"; then
    echo "check-marks: Secrets.swift still holds a URL" >&2; bad=1
fi

exit $bad
