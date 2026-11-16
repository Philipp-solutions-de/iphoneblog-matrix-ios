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
curl -fs -X PUT "$url/_matrix/client/v3/profile/@writer:localhost/displayname" -H "Authorization: Bearer $writer" \
    -d '{"displayname":"Stefan L."}' >/dev/null
rooms=(Allgemein Artikel)
allgemein=""
create() { # token, json → room id
    curl -fs -X POST "$url/_matrix/client/v3/createRoom" -H "Authorization: Bearer $1" -d "$2" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["room_id"])'
}
for name in "${rooms[@]}"; do
    alias=""; [[ "$name" == Allgemein ]] && alias=',"room_alias_name":"allgemein"'
    id="$(create "$token" "{\"name\":\"$name\",\"preset\":\"public_chat\"$alias}")"
    [[ "$name" == Allgemein ]] && allgemein="$id"
done

# As on the real server (2026-11-14_interfaces.md, "Matrix Blog feed"): #one is a space whose
# children are the #one rooms (Allgemein, Raum 2, as on the live server); the tester is a member.
one="$(create "$token" '{"name":"#one","preset":"private_chat","room_alias_name":"one","creation_content":{"type":"m.space"}}')"
curl -fs -X PUT "$url/_matrix/client/v3/rooms/$one/state/m.space.child/$allgemein" \
    -H "Authorization: Bearer $token" -d '{"via":["localhost"],"order":"a"}' >/dev/null
raum2="$(create "$token" '{"name":"Raum 2","preset":"public_chat"}')"
curl -fs -X PUT "$url/_matrix/client/v3/rooms/$one/state/m.space.child/$raum2" \
    -H "Authorization: Bearer $token" -d '{"via":["localhost"],"order":"b"}' >/dev/null

curl -fs -X POST "$url/_matrix/client/v3/join/$allgemein" -H "Authorization: Bearer $writer" -d '{}' >/dev/null
send() { # room, txn, json
    curl -fs -X PUT "$url/_matrix/client/v3/rooms/$1/send/m.room.message/$2" -H "Authorization: Bearer $writer" -d "$3" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["event_id"])'
}
send "$allgemein" t1 '{"msgtype":"m.text","body":"Hallo zusammen"}' >/dev/null
hello="$(send "$allgemein" t1b '{"msgtype":"m.text","body":"Hat jemand schon das neue iPad mini im Alltag?"}')"
send "$allgemein" t1c "{\"msgtype\":\"m.text\",\"body\":\"Ja, seit einer Woche. Der Dock-Adapter passt.\",\"m.relates_to\":{\"rel_type\":\"m.thread\",\"event_id\":\"$hello\"}}" >/dev/null
# A busy thread for the thread row: five more replies from three people (Tests/UITests/ThreadsUITests).
reader_password="$(openssl rand -hex 16)"
run register_new_matrix_user -c homeserver.yaml -u anna -p "$reader_password" --no-admin "$url" >/dev/null
anna="$(login anna "$reader_password")"
curl -fs -X PUT "$url/_matrix/client/v3/profile/@anna:localhost/displayname" -H "Authorization: Bearer $anna" \
    -d '{"displayname":"Anna K."}' >/dev/null
curl -fs -X POST "$url/_matrix/client/v3/join/$allgemein" -H "Authorization: Bearer $anna" -d '{}' >/dev/null
reply() { # token, txn, text
    curl -fs -X PUT "$url/_matrix/client/v3/rooms/$allgemein/send/m.room.message/$2" -H "Authorization: Bearer $1" \
        -d "{\"msgtype\":\"m.text\",\"body\":\"$3\",\"m.relates_to\":{\"rel_type\":\"m.thread\",\"event_id\":\"$hello\"}}" >/dev/null
}
reply "$anna" r1 "Ich warte noch auf das Cellular-Modell."
reply "$writer" r2 "Das kommt laut Gerüchten im Frühjahr."
reply "$token" r3 "Ich nutze meins vor allem zum Lesen."
reply "$anna" r4 "Mit welcher App liest du?"
reply "$writer" r5 "Bei mir sind es Comics in Panels."
send "$allgemein" t2 "{\"msgtype\":\"m.text\",\"body\":\"tester: schau mal\",\"m.mentions\":{\"user_ids\":[\"@$user:localhost\"]}}" >/dev/null
# A busy channel: ten messages and the rich set (six) after the mention. The SDK alone loses a mention behind six;
# the sign-in test and BadgesUITests check that it still counts (RoomListModel, ChatSession).
for n in $(seq 1 10); do
    send "$allgemein" "busy$n" "{\"msgtype\":\"m.text\",\"body\":\"Nachricht $n im vollen Kanal\"}" >/dev/null
done
# Then one message of every rich kind (formatting, link, reply, image, video, file), last in
# Allgemein where Tests/UITests/RichMessagesUITests.swift looks for them.
python3 "$here/scripts/test-rich-messages.py" "$url" "$writer" "$allgemein"

# The Blog room: the writer plays the article bot, one article root with the bot's field and a
# reply in its thread. The app joins it by itself (public).
blog="$(create "$writer" '{"name":"Blog","preset":"public_chat","room_alias_name":"blog"}')"
root="$(send "$blog" a1 '{"msgtype":"m.text","body":"Ein Testartikel\nhttps://www.iphoneblog.de/test/","de.iphoneblog.article":{"title":"Ein Testartikel","link":"https://www.iphoneblog.de/test/","teaser":"Zwei Zeilen Vorschau auf den Artikel.","image_url":null,"published_ts":1763200000000}}')"
send "$blog" a2 "{\"msgtype\":\"m.text\",\"body\":\"Erste Antwort\",\"m.relates_to\":{\"rel_type\":\"m.thread\",\"event_id\":\"$root\"}}" >/dev/null

# The same set in the article's thread (Tests/UITests/RichMessagesUITests.swift).
python3 "$here/scripts/test-rich-messages.py" "$url" "$writer" "$blog" "$root"
curl -fs -X POST "$url/_matrix/client/v3/logout" -H "Authorization: Bearer $token" >/dev/null

cat > "$here/build/test-homeserver.env" <<EOF
IPHONEBLOG_TEST_HOMESERVER=$url
IPHONEBLOG_TEST_USER=$user
IPHONEBLOG_TEST_PASSWORD=$password
IPHONEBLOG_TEST_USER2=anna
IPHONEBLOG_TEST_PASSWORD2=$reader_password
IPHONEBLOG_TEST_ROOMS='$(IFS=,; echo "${rooms[*]}")'
IPHONEBLOG_TEST_MENTION_ROOM=Allgemein
IPHONEBLOG_ONE_ALIAS=#one:localhost
IPHONEBLOG_BLOG_ALIAS=#blog:localhost
IPHONEBLOG_CHANNEL_ALIAS=#allgemein:localhost
IPHONEBLOG_TEST_CHANNEL_ROOM=$allgemein
IPHONEBLOG_TEST_CHANNEL_THREAD='$hello'
IPHONEBLOG_TEST_ARTICLE_ROOT='$root'
EOF
echo "test-homeserver: running at $url with user $user and rooms ${rooms[*]}"
