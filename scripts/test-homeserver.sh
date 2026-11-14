#!/usr/bin/env bash
# Start a throwaway Synapse on localhost:8008 for the integration test, with one
# user and two rooms. Writes the variables for scripts/build.sh to build/test-homeserver.env.
#
#   scripts/test-homeserver.sh start
#   scripts/test-homeserver.sh stop
#
# Needs uv (brew install uv). Everything lives in build/synapse and goes with it.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
dir="$here/build/synapse"
synapse_version="1.165.0"
url="http://127.0.0.1:8008"
run() { uv tool run --python 3.12 --from "matrix-synapse==$synapse_version" "$@"; }

case "${1:-start}" in
stop)
    if [[ -f "$dir/homeserver.pid" ]]; then kill "$(cat "$dir/homeserver.pid")" 2>/dev/null || true; fi
    exit 0
    ;;
start) ;;
*) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac

rm -rf "$dir"
mkdir -p "$dir"
cd "$dir"

run synapse_homeserver --server-name localhost --config-path homeserver.yaml \
    --generate-config --report-stats=no >/dev/null

cat >> homeserver.yaml <<EOF
pid_file: $dir/homeserver.pid
enable_registration: false
# A test server: no rate limits, so the test never waits.
rc_message: {per_second: 1000, burst_count: 1000}
rc_registration: {per_second: 1000, burst_count: 1000}
rc_login:
  address: {per_second: 1000, burst_count: 1000}
  account: {per_second: 1000, burst_count: 1000}
  failed_attempts: {per_second: 1000, burst_count: 1000}
rc_joins:
  local: {per_second: 1000, burst_count: 1000}
# As on our server: no encryption for any room type.
encryption_enabled_by_default_for_room_type: "off"
EOF
sed -i.bak 's/bind_addresses: \[.*\]/bind_addresses: ["127.0.0.1"]/' homeserver.yaml

run synapse_homeserver --config-path homeserver.yaml --daemonize
for _ in $(seq 1 60); do
    curl -fs "$url/_matrix/client/versions" >/dev/null && break
    sleep 1
done
curl -fs "$url/_matrix/client/versions" | grep -q '"org.matrix.simplified_msc3575":true' \
    || { echo "test-homeserver: no native sliding sync" >&2; exit 1; }

user="tester"
password="$(openssl rand -hex 16)"
run register_new_matrix_user -c homeserver.yaml -u "$user" -p "$password" --no-admin "$url" >/dev/null

token="$(curl -fs -X POST "$url/_matrix/client/v3/login" \
    -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$user\"},\"password\":\"$password\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
rooms=(Allgemein Artikel)
for name in "${rooms[@]}"; do
    curl -fs -X POST "$url/_matrix/client/v3/createRoom" -H "Authorization: Bearer $token" \
        -d "{\"name\":\"$name\",\"preset\":\"private_chat\"}" >/dev/null
done
curl -fs -X POST "$url/_matrix/client/v3/logout" -H "Authorization: Bearer $token" >/dev/null

cat > "$here/build/test-homeserver.env" <<EOF
IPHONEBLOG_TEST_HOMESERVER=$url
IPHONEBLOG_TEST_USER=$user
IPHONEBLOG_TEST_PASSWORD=$password
IPHONEBLOG_TEST_ROOMS=$(IFS=,; echo "${rooms[*]}")
EOF
echo "test-homeserver: running at $url with user $user and rooms ${rooms[*]}"
