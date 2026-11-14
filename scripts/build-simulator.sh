#!/usr/bin/env bash
# Build the prepared tree for the iOS Simulator, unsigned.
#   scripts/build-simulator.sh [prepared-tree] [derived-data]
# The app lands in <derived-data>/Build/Products/Debug-iphonesimulator/ElementX.app
# (the bundle keeps upstream's product name; its display name is ours).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
tree="${1:-$here/build/element-x-ios}"
dd="${2:-$here/build/DerivedData}"

cd "$tree"
set -o pipefail
xcodebuild \
    -project ElementX.xcodeproj \
    -scheme ElementX \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$dd" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build 2>&1 | tee "$here/build/xcodebuild.log" | grep -E '^(error|warning: .*Iphoneblog)|error:|\*\* BUILD' || true

grep -q '\*\* BUILD SUCCEEDED \*\*' "$here/build/xcodebuild.log"
