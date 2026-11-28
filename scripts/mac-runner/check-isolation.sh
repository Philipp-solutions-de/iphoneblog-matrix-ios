#!/usr/bin/env bash
# Prove, from inside a job on a self-hosted Mac, that the runner is walled off
# (docs/mac-runner.md, "Isolation"). Run by .github/workflows/mac-runner-check.yml, or by hand:
#   sudo -u ci -H scripts/mac-runner/check-isolation.sh
# Each private target below is open to Thorsten's own user, so "refused" here means the wall.
set -uo pipefail
fails=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
expect_closed() { # host port what
    if nc -z -G 3 "$1" "$2" >/dev/null 2>&1; then fail "$3 ($1:$2) is reachable"; else ok "$3 ($1:$2) is walled off"; fi
}

[[ "$(id -un)" == ci ]] && ok "runs as ci" || fail "runs as $(id -un), not ci"
id -Gn | tr ' ' '\n' | grep -qx admin && fail "ci is an admin" || ok "ci is no admin"
sudo -n true 2>/dev/null && fail "ci has sudo" || ok "ci has no sudo"
security list-keychains -d user 2>/dev/null | grep -q '/Users/ci/' && fail "ci has a keychain" || ok "ci has no keychain"

for home in /Users/*; do
    name="$(basename "$home")"
    case "$name" in Shared|ci|.*) continue ;; esac
    [[ -d "$home" ]] || continue
    if ls "$home" >/dev/null 2>&1; then fail "can list $home"; else ok "cannot read $home"; fi
done

expect_closed 10.10.0.1 22 "iron over WireGuard"
expect_closed 192.168.3.1 443 "the LAN router"
expect_closed 192.168.3.5 445 "the NAS"

curl -fsS -m 15 -o /dev/null https://api.github.com/zen && ok "the internet is reachable" || fail "no internet"
python3 -m http.server 18080 --bind 127.0.0.1 >/dev/null 2>&1 &
server=$!
sleep 1
curl -fsS -m 5 -o /dev/null http://127.0.0.1:18080/ && ok "loopback is reachable" || fail "no loopback"
kill "$server" 2>/dev/null

# Not a failure: disks set to ignore ownership are a choice of Thorsten's (docs/mac-runner.md).
mount | sed -nE 's/^.* on (\/Volumes\/.*) \(.*noowners.*$/\1/p' | while read -r mnt; do
    echo "note $mnt ignores ownership; ci can read it"
done

(( fails == 0 )) || { echo "$fails check(s) failed"; exit 1; }
