#!/bin/sh
# Keep the CI runner's network wall loaded (ci-runner.pf). Runs as root from the LaunchDaemon
# de.iphoneblog.ci-runner.pf at boot and every five minutes: a reload of /etc/pf.conf, or pf
# switched off, would otherwise drop it silently. Installed by setup.sh.
set -eu
dir="/Library/Application Support/ci-runner"
anchor="com.apple/ci-runner"
# /etc/pf.conf evaluates anchor "com.apple/*", so a rule set in com.apple/ci-runner applies
# without touching that file, which macOS updates rewrite.
if ! /sbin/pfctl -s info 2>/dev/null | grep -q 'Status: Enabled'; then
    /sbin/pfctl -E >/dev/null 2>&1
fi
if ! /sbin/pfctl -s rules 2>/dev/null | grep -q 'anchor "com.apple/\*"'; then
    /sbin/pfctl -f /etc/pf.conf 2>/dev/null
fi
want="$(/sbin/pfctl -nvf "$dir/ci-runner.pf" -a "$anchor" 2>/dev/null | grep -c '^block' || true)"
have="$(/sbin/pfctl -a "$anchor" -s rules 2>/dev/null | grep -c '^block' || true)"
if [ "$want" != "$have" ] || [ "$have" = 0 ]; then
    /sbin/pfctl -a "$anchor" -f "$dir/ci-runner.pf"
    echo "$(date '+%F %T') loaded $anchor" >&2
fi
