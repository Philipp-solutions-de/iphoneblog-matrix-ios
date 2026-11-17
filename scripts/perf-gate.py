#!/usr/bin/env python3
"""The performance gate (docs/performance.md).

    scripts/perf-gate.py build/perf.xcresult [--write-baseline]

Reads the numbers the performance tests measured (from build/perf.log, the lines xcodebuild
prints as "measured [<metric>, <unit>] average: …, values: [...]"), takes each metric's median,
and fails when:

- a metric is over its **budget** in scripts/perf-baseline.json ("budgets"; empty for the
  simulator, whose hitches are its own and not a phone's: the budget is checked on a device), or
- a gated metric is worse than its **baseline** by more than the relative tolerance *and* the
  absolute slack, both in the same file. Two conditions, because a simulator on a shared runner
  is noisy: 0.4 ms/s against a baseline of 0.2 is +100 % and means nothing. "per_test" gives
  one test its own slack (a cold launch on a busy runner varies by seconds).

A test that did not run, a metric it did not report, a log without numbers and a file without
baselines fail too: a gate that silently
measures less is no gate. `--write-baseline` writes the medians as the new baselines and keeps
budgets and tolerances. Writes a Markdown table to build/perf-report.md for the CI summary.
Standard library only.
"""
import json
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(HERE, "scripts", "perf-baseline.json")
LOG = os.path.join(HERE, "build", "perf.log")
REPORT = os.path.join(HERE, "build", "perf-report.md")

LINE = re.compile(r"Test Case '-\[PerfTests\.PerformanceTests (\w+)\]' measured \[(.+?), ([^\]]+)\] "
                  r"average: [^,]+, relative standard deviation: [^,]+, values: \[([^\]]*)\]")


def measured(log):
    out = {}
    with open(log, errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if not m:
                continue
            test, metric, unit, values = m.groups()
            vals = [float(v) for v in values.split(",") if v.strip()]
            if vals:
                out.setdefault(test, {})[metric] = {"median": statistics.median(vals), "unit": unit, "values": vals}
    return out


def main():
    write = "--write-baseline" in sys.argv
    if not os.path.exists(LOG):
        sys.exit(f"perf-gate: no {LOG}; run scripts/perf.sh first")
    got = measured(LOG)
    with open(BASELINE) as f:
        conf = json.load(f)

    if write:
        for test, metrics in got.items():
            for metric in conf["gated"]:
                if metric in metrics:
                    conf["baselines"].setdefault(test, {})[metric] = round(metrics[metric]["median"], 4)
        with open(BASELINE, "w") as f:
            json.dump(conf, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"perf-gate: baselines written for {len(got)} tests")

    failures = []
    if not got:
        failures.append("no measured numbers in the log")
    if not conf["baselines"]:
        failures.append("no baselines: run scripts/perf.sh baseline and commit scripts/perf-baseline.json")
    rows = ["| test | metric | median | baseline | budget | |", "|---|---|---:|---:|---:|---|"]
    for test, base in sorted(conf["baselines"].items()):
        if test not in got:
            failures.append(f"{test}: did not run or reported nothing")
            rows.append(f"| {test} | – | – | – | – | did not run |")
            continue
        for metric, baseline in sorted(base.items()):
            m = got[test].get(metric)
            budget = conf["budgets"].get(test, {}).get(metric, conf["budgets"].get("*", {}).get(metric))
            if m is None:
                failures.append(f"{test}: no {metric}")
                rows.append(f"| {test} | {metric} | – | {baseline} | {budget or ''} | missing |")
                continue
            value = m["median"]
            tol = conf["tolerance"]
            slack = tol.get("per_test", {}).get(test, {}).get(metric, tol["absolute"].get(metric, 0))
            verdict = "ok"
            if budget is not None and value > budget:
                verdict = "over budget"
                failures.append(f"{test}: {metric} {value:.3f} {m['unit']} over the budget {budget}")
            elif value > baseline * (1 + tol["relative"]) and value - baseline > slack:
                verdict = "regressed"
                failures.append(f"{test}: {metric} {value:.3f} {m['unit']} against baseline {baseline} "
                                f"(+{(value / baseline - 1) * 100 if baseline else 0:.0f} %, slack {slack})")
            rows.append(f"| {test} | {metric} | {value:.3f} {m['unit']} | {baseline} | "
                        f"{budget if budget is not None else ''} | {verdict} |")

    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w") as f:
        f.write("## Performance\n\n" + "\n".join(rows) + "\n")
        if failures:
            f.write("\n**Failed:**\n\n" + "\n".join(f"- {x}" for x in failures) + "\n")
    print("\n".join(rows))
    if failures:
        print("\nperf-gate: FAILED\n" + "\n".join(f"  {x}" for x in failures))
        sys.exit(1)
    print("\nperf-gate: passed")


if __name__ == "__main__":
    main()
