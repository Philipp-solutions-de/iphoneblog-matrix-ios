#!/usr/bin/env python3
"""Split the UI tests into shards of about equal time (docs/mac-runner.md, "Test shards").

    scripts/ui-shards.py ENUMERATED.json SHARDS SHARD [--preload SECONDS]

ENUMERATED.json is what `xcodebuild test-without-building -enumerate-tests
-test-enumeration-format json -test-enumeration-style flat` writes for the UITests xctestrun.
Prints the tests of shard SHARD (1-based), one `UITests/Class/test` per line, for
`-only-testing:`. Times come from scripts/ui-test-times.json (seconds per test, measured on
the Mac Studio); a test not in it counts as the median. --preload is time shard 1 spends on
other work first (the unit and sign-in tests). Every shard computes the same split, and the
script fails unless the shards together hold every enumerated test exactly once: nothing is
skipped, nothing runs twice.
"""
import json
import pathlib
import statistics
import sys


def split(tests, times, shards, preload=0.0):
    known = [times[t] for t in tests if t in times]
    default = statistics.median(known) if known else 60.0
    load = [0.0] * shards
    load[0] = preload
    parts = [[] for _ in range(shards)]
    # Longest first, each to the shard with the least time so far; names break ties, so the
    # split is the same on every machine.
    for t in sorted(tests, key=lambda t: (-times.get(t, default), t)):
        i = min(range(shards), key=lambda i: (load[i], i))
        parts[i].append(t)
        load[i] += times.get(t, default)
    return parts, load


def main():
    args = sys.argv[1:]
    preload = 0.0
    if "--preload" in args:
        i = args.index("--preload")
        preload = float(args[i + 1])
        del args[i:i + 2]
    if len(args) != 3:
        sys.exit(__doc__)
    enumerated, shards, shard = args[0], int(args[1]), int(args[2])
    data = json.loads(pathlib.Path(enumerated).read_text())
    if data.get("errors"):
        sys.exit(f"ui-shards: enumeration reported errors: {data['errors']}")
    tests = []
    for value in data["values"]:
        for entry in value["enabledTests"]:
            ident = entry["identifier"].removesuffix("()")
            if not ident.startswith("UITests/"):
                sys.exit(f"ui-shards: unexpected test {ident}")
            tests.append(ident.removeprefix("UITests/"))
    if not tests:
        sys.exit("ui-shards: no tests enumerated")
    times = json.loads((pathlib.Path(__file__).parent / "ui-test-times.json").read_text())
    parts, load = split(tests, times, shards, preload)

    flat = [t for p in parts for t in p]
    if sorted(flat) != sorted(tests) or len(set(flat)) != len(flat):
        sys.exit("ui-shards: the shards do not hold every test exactly once")
    for i, (p, l) in enumerate(zip(parts, load), 1):
        print(f"shard {i}/{shards}: {len(p)} tests, about {l / 60:.0f} min", file=sys.stderr)
    for t in parts[shard - 1]:
        print(f"UITests/{t}")


if __name__ == "__main__":
    main()
