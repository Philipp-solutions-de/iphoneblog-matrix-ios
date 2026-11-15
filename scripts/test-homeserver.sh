#!/usr/bin/env bash
# Start a throwaway Synapse on localhost:8008 for the integration test: the user "tester",
# two rooms, and a second user who writes a message and mentions the tester in Allgemein. Writes the variables for scripts/build.sh to build/test-homeserver.env.
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

login() {
    curl -fs -X POST "$url/_matrix/client/v3/login" \
        -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$1\"},\"password\":\"$2\"}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

# A second person who writes to the tester: one message and one mention in Allgemein.
writer_password="$(openssl rand -hex 16)"
run register_new_matrix_user -c homeserver.yaml -u writer -p "$writer_password" --no-admin "$url" >/dev/null

token="$(login "$user" "$password")"
writer="$(login writer "$writer_password")"
rooms=(Allgemein Artikel)
allgemein=""
create() { # token, json → room id
    curl -fs -X POST "$url/_matrix/client/v3/createRoom" -H "Authorization: Bearer $1" -d "$2" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["room_id"])'
}
for name in "${rooms[@]}"; do
    id="$(create "$token" "{\"name\":\"$name\",\"preset\":\"public_chat\"}")"
    [[ "$name" == Allgemein ]] && allgemein="$id"
done

# As on the real server (2026-11-14_interfaces.md, "Matrix Blog feed"): #one is a space whose
# children are the #one-Chat channels; the tester is a member, Allgemein its child.
one="$(create "$token" '{"name":"#one","preset":"private_chat","room_alias_name":"one","creation_content":{"type":"m.space"}}')"
curl -fs -X PUT "$url/_matrix/client/v3/rooms/$one/state/m.space.child/$allgemein" \
    -H "Authorization: Bearer $token" -d '{"via":["localhost"]}' >/dev/null

curl -fs -X POST "$url/_matrix/client/v3/join/$allgemein" -H "Authorization: Bearer $writer" -d '{}' >/dev/null
send() { # room, txn, json
    curl -fs -X PUT "$url/_matrix/client/v3/rooms/$1/send/m.room.message/$2" -H "Authorization: Bearer $writer" -d "$3" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["event_id"])'
}
send "$allgemein" t1 '{"msgtype":"m.text","body":"Hallo zusammen"}' >/dev/null
send "$allgemein" t2 "{\"msgtype\":\"m.text\",\"body\":\"tester: schau mal\",\"m.mentions\":{\"user_ids\":[\"@$user:localhost\"]}}" >/dev/null

# The Blog room: the writer plays the article bot, one article root with the bot's field and a
# reply in its thread. The app joins it by itself (public).
blog="$(create "$writer" '{"name":"Blog","preset":"public_chat","room_alias_name":"blog"}')"
root="$(send "$blog" a1 '{"msgtype":"m.text","body":"Ein Testartikel\nhttps://www.iphoneblog.de/test/","de.iphoneblog.article":{"title":"Ein Testartikel","link":"https://www.iphoneblog.de/test/","teaser":"Zwei Zeilen Vorschau auf den Artikel.","image_url":null,"published_ts":1763200000000}}')"
send "$blog" a2 "{\"msgtype\":\"m.text\",\"body\":\"Erste Antwort\",\"m.relates_to\":{\"rel_type\":\"m.thread\",\"event_id\":\"$root\"}}" >/dev/null
curl -fs -X POST "$url/_matrix/client/v3/logout" -H "Authorization: Bearer $token" >/dev/null

cat > "$here/build/test-homeserver.env" <<EOF
IPHONEBLOG_TEST_HOMESERVER=$url
IPHONEBLOG_TEST_USER=$user
IPHONEBLOG_TEST_PASSWORD=$password
IPHONEBLOG_TEST_ROOMS=$(IFS=,; echo "${rooms[*]}")
IPHONEBLOG_TEST_MENTION_ROOM=Allgemein
IPHONEBLOG_ONE_ALIAS=#one:localhost
IPHONEBLOG_BLOG_ALIAS=#blog:localhost
IPHONEBLOG_TEST_ARTICLE_TITLE="Ein Testartikel"
EOF
echo "test-homeserver: running at $url with user $user and rooms ${rooms[*]}"
