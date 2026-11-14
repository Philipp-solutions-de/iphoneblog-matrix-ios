#!/usr/bin/env bash
# Build an iphoneblog source tree from an Element X release.
#
#   scripts/prepare.sh [release-tag] [output-dir]
#
# Without a tag it takes upstream's newest release. The steps, in order:
#   1. clone element-hq/element-x-ios at the tag (no LFS: the app needs none of it)
#   2. copy overlay/ over the tree (our own files: hooks, icon, images)
#   3. apply patches/*.patch with git apply --3way (empty today; for changes a hook cannot make)
#   4. run scripts/brand.py (name, identifiers, domains, secrets, strings, accent colour)
#   5. run xcodegen
# It prints the tag it used on the last line, as "tag=<tag>".
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
upstream="https://github.com/element-hq/element-x-ios.git"

tag="${1:-}"
out="${2:-$here/build/element-x-ios}"

if [[ -z "$tag" ]]; then
    tag="$(git ls-remote --tags --refs "$upstream" 'release/*' \
        | awk '{print $2}' | sed 's#refs/tags/##' \
        | grep -E '^release/[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -t/ -k2 -V | tail -1)"
    [[ -n "$tag" ]] || { echo "prepare.sh: found no release tag upstream" >&2; exit 1; }
fi
echo "prepare.sh: upstream $tag into $out"

rm -rf "$out"
mkdir -p "$(dirname "$out")"
# A global git-lfs filter that requires a missing binary breaks the checkout; switch it off here.
GIT_LFS_SKIP_SMUDGE=1 git -c filter.lfs.required=false -c filter.lfs.smudge= -c filter.lfs.process= \
    clone --quiet --depth 1 --branch "$tag" "$upstream" "$out"

echo "prepare.sh: overlay"
# An image set or icon in overlay/ replaces upstream's whole folder, so no Element file stays behind.
(cd "$here/overlay" && find . -type d \( -name '*.imageset' -o -name '*.icon' \)) | while read -r dir; do
    [[ -d "$out/$dir" ]] || { echo "prepare.sh: upstream has no $dir any more" >&2; exit 1; }
    rm -rf "${out:?}/$dir"
done
cp -R "$here/overlay/." "$out/"

shopt -s nullglob
for patch in "$here"/patches/*.patch; do
    echo "prepare.sh: patch $(basename "$patch")"
    git -C "$out" apply --3way --whitespace=nowarn "$patch"
done
shopt -u nullglob

echo "prepare.sh: brand"
python3 "$here/scripts/brand.py" "$out" "$here/brand.env"

echo "prepare.sh: guard against Element marks"
"$here/scripts/check-marks.sh" "$out"

echo "prepare.sh: xcodegen"
(cd "$out" && xcodegen --quiet)

echo "tag=$tag"
