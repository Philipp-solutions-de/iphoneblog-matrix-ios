# Patches

Changes that no hook in `overlay/` and no edit in `scripts/brand.py` can make. `scripts/prepare.sh`
applies every `*.patch` here with `git apply --3way`, in name order. Make one with
`git diff > patches/NNN-what.patch` inside a prepared tree. Empty today.
