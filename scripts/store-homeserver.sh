#!/usr/bin/env bash
# A throwaway Synapse on 127.0.0.1:8018 for the App Store screenshots: server name iphoneblog.de,
# as on live, an invented cast and a staged German conversation (scripts/store-seed.py). Writes
# build/store-homeserver.env, which scripts/store-screenshots.sh reads. Port 8018, so it runs next
# to the test server (scripts/test-homeserver.sh, port 8008) without touching it.
#
#   scripts/store-homeserver.sh start
#   scripts/store-homeserver.sh stop
#
# Needs uv (brew install uv). Everything lives in build/store-synapse and goes with it.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
dir="$here/build/store-synapse"
synapse_version="1.165.0"
port=8018
url="http://127.0.0.1:$port"
run() { uv tool run --python 3.12 --from "matrix-synapse==$synapse_version" "$@"; }

case "${1:-start}" in
stop)
    if [[ -f "$dir/homeserver.pid" ]]; then kill "$(cat "$dir/homeserver.pid")" 2>/dev/null || true; fi
    exit 0
    ;;
start) ;;
*) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac

if [[ -f "$dir/homeserver.pid" ]]; then kill "$(cat "$dir/homeserver.pid")" 2>/dev/null || true; sleep 1; fi
rm -rf "$dir"
mkdir -p "$dir"
cd "$dir"

run synapse_homeserver --server-name iphoneblog.de --config-path homeserver.yaml \
    --generate-config --report-stats=no >/dev/null

cat >> homeserver.yaml <<EOF
pid_file: $dir/homeserver.pid
enable_registration: false
rc_message: {per_second: 1000, burst_count: 1000}
rc_registration: {per_second: 1000, burst_count: 1000}
rc_login:
  address: {per_second: 1000, burst_count: 1000}
  account: {per_second: 1000, burst_count: 1000}
  failed_attempts: {per_second: 1000, burst_count: 1000}
rc_joins:
  local: {per_second: 1000, burst_count: 1000}
encryption_enabled_by_default_for_room_type: "off"
EOF
sed -i.bak -e 's/bind_addresses: \[.*\]/bind_addresses: ["127.0.0.1"]/' -e "s/port: 8008/port: $port/" homeserver.yaml

run synapse_homeserver --config-path homeserver.yaml --daemonize
for _ in $(seq 1 60); do
    curl -fs "$url/_matrix/client/versions" >/dev/null && break
    sleep 1
done
curl -fs "$url/_matrix/client/versions" >/dev/null || { echo "store-homeserver: Synapse did not start" >&2; exit 1; }

secret="$(sed -n 's/^registration_shared_secret: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' homeserver.yaml)"
python3 "$here/scripts/store-seed.py" "$url" "$secret" > "$here/build/store-homeserver.env"
echo "store-homeserver: running at $url, env in build/store-homeserver.env"
