#!/bin/sh
# A laptop takes jobs only on power (docs/mac-runner.md, "On a laptop"). Runs as root from the
# LaunchDaemon de.iphoneblog.ci-runner.power at boot and every 30 seconds, only on a Mac with
# a battery; installed by setup.sh.
#
# On power: starts every runner, once Xcode is ready (xcode-upkeep.sh leaves the file
# xcode-ready). On battery: stops them, but never in the middle of a run. A run sent here
# queues its test shards on this Mac's label after its build; a runner stopped between the
# two would strand them for 24 hours. So it waits until no job has run for two checks in a
# row (a minute), and the laptop finishes the run it started on battery.
#
# Every GitHub runner on this Mac counts: the walled-off instances of user ci (LaunchDaemons
# de.iphoneblog.ci-runner, -2 …) and a runner a user installed with the runner's own svc.sh
# (LaunchAgents actions.runner.*, such as trebuchet-testlab's m1lab).
set -eu
dir="/Library/Application Support/ci-runner"
log() { echo "$(date '+%F %T') $*"; }

daemons() { # the walled-off instances: "system/<label> <plist>"
    for plist in /Library/LaunchDaemons/de.iphoneblog.ci-runner.plist /Library/LaunchDaemons/de.iphoneblog.ci-runner-[0-9]*.plist; do
        [ -f "$plist" ] && echo "system/$(basename "$plist" .plist) $plist"
    done
    return 0
}
agents() { # runners installed by svc.sh: "gui/<uid>/<label> <plist>", only while that user is signed in
    for plist in /Users/*/Library/LaunchAgents/actions.runner.*.plist; do
        [ -f "$plist" ] || continue
        uid="$(stat -f %u "$plist")"
        launchctl print "gui/$uid" >/dev/null 2>&1 || continue
        echo "gui/$uid/$(basename "$plist" .plist) $plist"
    done
    return 0
}
services() { daemons; agents; }

# A hold counts as battery: while /Users/Shared/ci-runner-hold exists (any user may create it,
# e.g. trebuchet-testlab's ./lab before a game run that must not share the Mac), the runners
# finish their run, stop, and start again once the file is gone.
hold=/Users/Shared/ci-runner-hold
on_power() { [ ! -e "$hold" ] && pmset -g ps | head -1 | grep -q "'AC Power'"; }
job_running() { pgrep -f 'Runner\.Worker' >/dev/null 2>&1; }

if on_power; then
    rm -f "$dir/idle-on-battery"
    services | while read -r target plist; do
        # The walled-off instances wait for Xcode; a user's own runner does not need it.
        case "$target" in system/*) [ -f "$dir/xcode-ready" ] || continue ;; esac
        if ! launchctl print "$target" >/dev/null 2>&1; then
            launchctl bootstrap "${target%/*}" "$plist" && log "on power: $target started"
        fi
    done
    exit 0
fi

# On battery.
running="$(services | while read -r target plist; do
    launchctl print "$target" >/dev/null 2>&1 && echo "$target"; done)"
[ -n "$running" ] || exit 0
if job_running; then
    rm -f "$dir/idle-on-battery"
    log "on battery, a job runs: the runners stay until the run is done"
    exit 0
fi
if [ ! -f "$dir/idle-on-battery" ]; then
    touch "$dir/idle-on-battery"
    exit 0
fi
for target in $running; do
    launchctl bootout "$target" && log "on battery: $target stopped"
done
rm -f "$dir/idle-on-battery"
