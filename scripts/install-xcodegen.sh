#!/usr/bin/env bash
# Install a pinned XcodeGen release, checked against its SHA-256, into $1 (default build/tools)
# and print the bin directory. Used by CI instead of Homebrew, so jobs that hold the Apple
# key run only tools whose bytes we pinned.
set -euo pipefail
version="2.46.0"
sha256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
dest="${1:-build/tools}"
mkdir -p "$dest"
zip="$dest/xcodegen-$version.zip"
curl -fsSL -o "$zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
echo "$sha256  $zip" | shasum -a 256 -c - >&2
unzip -qo "$zip" -d "$dest"
echo "$(cd "$dest/xcodegen/bin" && pwd)"
