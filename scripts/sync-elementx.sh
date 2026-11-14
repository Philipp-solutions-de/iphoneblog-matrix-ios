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
# A line "!path" leaves out that file or folder, also inside a listed folder.
list_files() {
    local excludes
    excludes="$(grep -E '^!' "$vendor/paths.txt" | sed 's/^!//' || true)"
    grep -v -E '^\s*(#|$|!)' "$vendor/paths.txt" | while read -r path; do
        if [[ -d "$pristine/$path" ]]; then
            (cd "$pristine" && find "$path" -type f ! -name '.DS_Store')
        elif [[ -f "$pristine/$path" ]]; then
            echo "$path"
        else
            echo "sync-elementx: $path is not in $tag" >&2
            exit 1
        fi
    done | sort -u | while read -r file; do
        skip=0
        while read -r ex; do
            [[ -n "$ex" && ( "$file" == "$ex" || "$file" == "$ex/"* ) ]] && { skip=1; break; }
        done <<< "$excludes"
        [[ $skip == 0 ]] && echo "$file"
    done
}

patch_name() { echo "${1//\//__}.patch"; }

# The listed files as copied from the tag, previews stripped: what patches/ applies to.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage() {
    local swift=()
    while read -r path; do
        mkdir -p "$work/$(dirname "$path")"
        cp "$pristine/$path" "$work/$path"
        [[ "$path" == *.swift ]] && swift+=("$work/$path")
    done < <(list_files)
    python3 "$vendor/strip-previews.py" "${swift[@]}"
}
stage

# The strip script shapes the base that patches/ is cut against. Patches saved after it changed
# but before a sync would record its effect as our edits, so saving then is refused.
stamp="$vendor/.strip-stamp"
strip_hash="$(shasum "$vendor/strip-previews.py" | cut -d' ' -f1)"

case "$mode" in
    save)
        if [[ -f "$stamp" && "$(cat "$stamp")" != "$strip_hash" ]]; then
            echo "sync-elementx: strip-previews.py changed since the last sync. Undo that change, save your" >&2
            echo "patches, then change it again and run a sync before saving." >&2
            exit 1
        fi
        rm -f "$vendor"/patches/*.patch
        mkdir -p "$vendor/patches"
        count=0
        while read -r path; do
            if [[ ! -f "$vendor/$path" ]]; then
                # Newly listed: bring it in as published. (To drop a file, take it out of paths.txt.)
                mkdir -p "$vendor/$(dirname "$path")"
                cp "$work/$path" "$vendor/$path"
            elif ! cmp -s "$work/$path" "$vendor/$path"; then
                diff -u --label "a/$path" --label "b/$path" "$work/$path" "$vendor/$path" \
                    > "$vendor/patches/$(patch_name "$path")" || true
                count=$((count + 1))
            fi
        done < <(list_files)
        echo "sync-elementx: $count patches in Vendor/ElementX/patches"
        ;;
    sync|check)
        shopt -s nullglob
        for p in "$vendor"/patches/*.patch; do
            target="$(basename "$p" .patch)"; target="${target//__//}"
            if ! patch --quiet --forward --no-backup-if-mismatch "$work/$target" < "$p"; then
                echo "sync-elementx: $(basename "$p") no longer applies to $tag; fix it by hand, then --save-patches" >&2
                exit 1
            fi
        done
        if [[ "$mode" == "check" ]]; then
            fail=0
            for top in ElementX compound-ios; do
                [[ -d "$work/$top" || -d "$vendor/$top" ]] || continue
                diff -rq -x .DS_Store -x .swiftpm "$work/$top" "$vendor/$top" || fail=1
            done
            [[ $fail == 0 ]] && echo "sync-elementx: Vendor/ElementX matches $tag plus patches"
            exit $fail
        fi
        rm -rf "$vendor/ElementX" "$vendor/compound-ios"
        for top in ElementX compound-ios; do
            [[ -d "$work/$top" ]] && cp -R "$work/$top" "$vendor/$top"
        done
        echo "$tag" > "$vendor/UPSTREAM.tag"
        echo "$strip_hash" > "$stamp"
        patches=("$vendor"/patches/*.patch)
        echo "sync-elementx: Vendor/ElementX now holds $tag plus ${#patches[@]} patches"
        ;;
esac
