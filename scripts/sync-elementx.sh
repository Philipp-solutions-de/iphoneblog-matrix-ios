#!/usr/bin/env bash
# Copy Element X iOS's chat views into Vendor/ElementX and reapply our local edits.
#
#   scripts/sync-elementx.sh                 re-sync from the tag in Vendor/ElementX/UPSTREAM.tag
#   scripts/sync-elementx.sh <tag>           re-sync from another release tag, e.g. release/26.12.0
#   scripts/sync-elementx.sh --save-patches  turn the current edits under Vendor/ElementX into
#                                            Vendor/ElementX/patches/*.patch (one per upstream file)
#   scripts/sync-elementx.sh --check         fail if Vendor/ElementX differs from tag + patches
#
# Vendor/ElementX/paths.txt lists every copied file or folder, relative to the Element X
# repository root. Our own files sit in Vendor/ElementX/Shim/ and are never touched here.
# A re-sync is a diff to review (git diff Vendor/), not a hand merge. See docs/architecture.md,
# "Kept apart so it can be re-synced or swapped".
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
vendor="$here/Vendor/ElementX"
cache="$here/build/elementx"
upstream_url="https://github.com/element-hq/element-x-ios.git"

mode="sync"
tag="$(cat "$vendor/UPSTREAM.tag")"
case "${1:-}" in
    --save-patches) mode="save" ;;
    --check) mode="check" ;;
    "") ;;
    *) tag="$1" ;;
esac

# A pristine copy of the tag, without Git LFS (the snapshots it stores are not needed).
pristine="$cache/${tag//\//_}"
if [[ ! -d "$pristine/.git" ]]; then
    rm -rf "$pristine"
    mkdir -p "$cache"
    GIT_LFS_SKIP_SMUDGE=1 git -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false \
        clone --quiet --depth 1 --branch "$tag" "$upstream_url" "$pristine"
fi

# Every listed path, expanded to files, comments and blank lines skipped.
list_files() {
    grep -v -E '^\s*(#|$)' "$vendor/paths.txt" | while read -r path; do
        if [[ -d "$pristine/$path" ]]; then
            (cd "$pristine" && find "$path" -type f ! -name '.DS_Store')
        elif [[ -f "$pristine/$path" ]]; then
            echo "$path"
        else
            echo "sync-elementx: $path is not in $tag" >&2
            exit 1
        fi
    done | sort -u
}

patch_name() { echo "${1//\//__}.patch"; }

case "$mode" in
    save)
        rm -f "$vendor"/patches/*.patch
        mkdir -p "$vendor/patches"
        count=0
        while read -r path; do
            if [[ ! -f "$vendor/$path" ]]; then
                echo "sync-elementx: $path is listed but missing; take it out of paths.txt instead" >&2
                exit 1
            elif ! cmp -s "$pristine/$path" "$vendor/$path"; then
                diff -u --label "a/$path" --label "b/$path" "$pristine/$path" "$vendor/$path" \
                    > "$vendor/patches/$(patch_name "$path")" || true
                count=$((count + 1))
            fi
        done < <(list_files)
        echo "sync-elementx: $count patches in Vendor/ElementX/patches"
        ;;
    sync|check)
        work="$(mktemp -d)"
        trap 'rm -rf "$work"' EXIT
        while read -r path; do
            mkdir -p "$work/$(dirname "$path")"
            cp "$pristine/$path" "$work/$path"
        done < <(list_files)
        shopt -s nullglob
        for p in "$vendor"/patches/*.patch; do
            if ! (cd "$work" && patch --quiet -p1 --no-backup-if-mismatch < "$p"); then
                echo "sync-elementx: $(basename "$p") no longer applies to $tag; fix it by hand, then --save-patches" >&2
                exit 1
            fi
        done
        if [[ "$mode" == "check" ]]; then
            fail=0
            for top in ElementX compound-ios; do
                [[ -d "$work/$top" || -d "$vendor/$top" ]] || continue
                diff -rq -x .DS_Store "$work/$top" "$vendor/$top" || fail=1
            done
            [[ $fail == 0 ]] && echo "sync-elementx: Vendor/ElementX matches $tag plus patches"
            exit $fail
        fi
        rm -rf "$vendor/ElementX" "$vendor/compound-ios"
        for top in ElementX compound-ios; do
            [[ -d "$work/$top" ]] && cp -R "$work/$top" "$vendor/$top"
        done
        echo "$tag" > "$vendor/UPSTREAM.tag"
        patches=("$vendor"/patches/*.patch)
        echo "sync-elementx: Vendor/ElementX now holds $tag plus ${#patches[@]} patches"
        ;;
esac
