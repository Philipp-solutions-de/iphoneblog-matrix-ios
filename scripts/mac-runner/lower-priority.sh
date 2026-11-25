#!/bin/sh
# Keep every process of the runner's user at the lowest CPU priority, so CI never makes
# Thorsten's own work on the Mac stutter (docs/mac-runner.md, "Priority").
#
#   scripts/mac-runner/lower-priority.sh          loop: every 5 s, all of this user's processes
#   scripts/mac-runner/lower-priority.sh report   print them with nice and priority
#
# Started by each job on the Mac (build.yml); the runner ends it with the job. A loop over the
# user, not a wrapper around the job, because the simulators, XCBBuildService, SWBBuildService
# and the compilers they start are launched by launchd and XPC outside the job's process tree.
# Each gets nice 20 and PRIO_DARWIN_BG (taskpolicy -b): the background QoS class, which on Apple
# silicon runs on the efficiency cores and yields the disk as well. A Mac whose runner .env says
# MAC_PRIORITY=nice (setup.sh --priority nice, the MacBook Pro) gets nice 20 only: every core,
# but anything of Thorsten's comes first.
me="$(id -u)"
background=yes
[ "${MAC_PRIORITY:-background}" != nice ] || background=no
if [ "${1:-}" = report ]; then
    ps -U "$me" -o pid=,nice=,pri=,comm= | awk '{printf "%7s nice %3s pri %3s %s\n", $1, $2, $3, $4}'
    exit 0
fi
while :; do
    for pid in $(pgrep -U "$me"); do
        renice 20 -p "$pid" >/dev/null 2>&1
        [ "$background" = no ] || taskpolicy -b -p "$pid" >/dev/null 2>&1
    done
    sleep 5
done
