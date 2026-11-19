#!/usr/bin/env python3
"""Seeds the store server (scripts/store-homeserver.sh) for the App Store screenshots.

Usage: store-seed.py <homeserver url> <registration shared secret>  > build/store-homeserver.env

Everyone here is invented: the demo member Lena Hoffmann, whose account the screenshots show,
and four other members. The article in the discussion is a real public one from www, posted by
an "iPhoneBlog" bot as the live article bot does. The talk is German and about the news: an
article's discussion, the #one room about episode #532, a thread about the Passwords app, and
a mention of Lena for Für dich. Prints the variables for scripts/store-screenshots.sh.
"""

import hashlib
import hmac
import json
import secrets
import sys
import urllib.parse
import urllib.request
import uuid

BASE, SECRET = sys.argv[1:3]
SERVER = "iphoneblog.de"


def call(path, token=None, method="POST", body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def register(user, name):
    password = secrets.token_hex(16)
    nonce = call("/_synapse/admin/v1/register", method="GET")["nonce"]
    mac = hmac.new(SECRET.encode(), b"\0".join(x.encode() for x in (nonce, user, password, "notadmin")),
                   hashlib.sha1).hexdigest()
    token = call("/_synapse/admin/v1/register",
                 body={"nonce": nonce, "username": user, "password": password, "admin": False, "mac": mac})["access_token"]
    call(f"/_matrix/client/v3/profile/@{user}:{SERVER}/displayname", token, "PUT", {"displayname": name})
    return token, password


def room(token, body):
    return call("/_matrix/client/v3/createRoom", token, body=body)["room_id"]


def join(token, room_id):
    call(f"/_matrix/client/v3/join/{urllib.parse.quote(room_id)}", token, body={})


def send(token, room_id, content, thread=None):
    if thread:
        content["m.relates_to"] = {"rel_type": "m.thread", "event_id": thread, "is_falling_back": True}
    path = f"/_matrix/client/v3/rooms/{urllib.parse.quote(room_id)}/send/m.room.message/{uuid.uuid4().hex}"
    return call(path, token, "PUT", content)["event_id"]


def text(body):
    return {"msgtype": "m.text", "body": body}


def mention(user, name, rest):
    link = f"https://matrix.to/#/@{user}:{SERVER}"
    return {"msgtype": "m.text", "body": f"{name}: {rest}", "format": "org.matrix.custom.html",
            "formatted_body": f'<a href="{link}">{name}</a>: {rest}',
            "m.mentions": {"user_ids": [f"@{user}:{SERVER}"]}}


lena, lena_password = register("lena.hoffmann", "Lena Hoffmann")
markus, _ = register("markus.brandt", "Markus Brandt")
julia, _ = register("julia.wendt", "Julia Wendt")
tobias, _ = register("tobias.kern", "Tobias Kern")
sabine, _ = register("sabine.roth", "Sabine Roth")
bot, _ = register("blog", "iPhoneBlog")
people = [lena, markus, julia, tobias, sabine]

# #one: a space whose children are the members' rooms, as on live.
one = room(bot, {"name": "#one", "preset": "public_chat", "room_alias_name": "one", "creation_content": {"type": "m.space"}})
allgemein = room(bot, {"name": "Allgemein", "preset": "public_chat", "room_alias_name": "allgemein"})
podcast = room(bot, {"name": "Podcast", "preset": "public_chat"})
for order, child in (("a", allgemein), ("b", podcast)):
    call(f"/_matrix/client/v3/rooms/{urllib.parse.quote(one)}/state/m.space.child/{urllib.parse.quote(child)}",
         bot, "PUT", {"via": [SERVER], "order": order})
blog = room(bot, {"name": "Blog", "preset": "public_chat", "room_alias_name": "blog"})
for token in people:
    for r in (one, allgemein, podcast, blog):
        join(token, r)
# Lena has read the posting notice, as any member who has written before.
call(f"/_matrix/client/v3/user/%40lena.hoffmann%3A{SERVER}/account_data/de.iphoneblog.posting_notice",
     lena, "PUT", {"acknowledged": True})

# The article's discussion: a real public article from www, its fields as the article bot sends them.
article = {
    "title": "„Entsperren per Gesicht“ ungleich Face ID",
    "link": "https://www.iphoneblog.de/2026/11/17/entsperren-per-gesicht-ungleich-face-id/",
    "teaser": "„Entsperren per Gesichtserkennung“ – ähnlich wie beim HomeView – erreicht das iPhone Duo "
              "… unerwartet. Apple beziffert die Wahrscheinlichkeit einer fälschlichen Authentifizierung …",
    "image_url": "https://www.iphoneblog.de/wp-content/uploads/2026/11/iPhoneBlog.de_smartphone-face-recognition-setup-hands.png",
    "published_ts": 1794927733000,
}
root = send(bot, blog, {"msgtype": "m.text", "body": f"{article['title']}\n{article['link']}",
                        "de.iphoneblog.article": article})
for token, line in (
    (markus, "Gut, dass Apple das so klar trennt. Ich hätte beides für dasselbe gehalten."),
    (julia, "Die Zahl zur Fehlerquote hätte ich gern direkt neben der von Face ID gesehen."),
    (lena, "Mir reicht das zum Entsperren völlig. Wichtig ist nur, dass es auch mit Brille klappt."),
    (tobias, "Weiß jemand schon, ob Banking-Apps das wie Face ID behandeln?"),
    (sabine, "Ich würde abwarten, bis sich die Banken dazu äußern. Bis dahin eben der Code."),
):
    send(token, blog, text(line), root)

# Allgemein: the members talk about the news, one thread, and a mention of Lena last.
send(markus, allgemein, text("Hat schon jemand #532 gesehen? Ich probiere Quiche jetzt auch als Standardbrowser."))
send(julia, allgemein, text("Ja, gestern Abend. Mir gefällt, wie aufgeräumt das wirkt."))
send(tobias, allgemein, text("Ich bleibe vorerst bei Safari, aber die Folge hat mich neugierig gemacht."))
send(lena, allgemein, text("Bei mir hat der Umzug der Lesezeichen keine fünf Minuten gedauert."))
thread = send(sabine, allgemein, text("Was nutzt ihr eigentlich für Passwörter, seit es die Passwörter-App gibt?"))
for token, line in (
    (markus, "Komplett umgestiegen. Die Codes für die Zwei-Faktor-Anmeldung sind auch gleich drin."),
    (lena, "Ich auch. Nur die mit der Familie geteilten Passwörter musste ich neu anlegen."),
    (julia, "Ich hänge noch an meinem alten Passwortmanager, wegen Windows im Büro."),
    (tobias, "Mit iCloud für Windows klappt das inzwischen ganz gut."),
    (sabine, "Danke euch, dann traue ich mich ran."),
):
    send(token, allgemein, text(line), thread)
send(markus, allgemein, mention("lena.hoffmann", "Lena Hoffmann", "Wie hast du die Lesezeichen rübergeholt?"))
send(julia, podcast, text("Die Kapitelmarken in der neuen Folge sind super, danke dafür!"))

# Lena's own read state: everything up to now is read except Markus's mention.
for r in (one, podcast, blog):
    last = call(f"/_matrix/client/v3/rooms/{urllib.parse.quote(r)}/messages?dir=b&limit=1", lena, "GET")["chunk"]
    if last:
        call(f"/_matrix/client/v3/rooms/{urllib.parse.quote(r)}/receipt/m.read/{urllib.parse.quote(last[0]['event_id'])}",
             lena, body={})

print(f"IPHONEBLOG_TEST_HOMESERVER={BASE}")
print("IPHONEBLOG_TEST_USER=lena.hoffmann")
print(f"IPHONEBLOG_TEST_PASSWORD={lena_password}")
print(f"IPHONEBLOG_ONE_ALIAS=#one:{SERVER}")
print(f"IPHONEBLOG_BLOG_ALIAS=#blog:{SERVER}")
print(f"IPHONEBLOG_CHANNEL_ALIAS=#allgemein:{SERVER}")
print(f"IPHONEBLOG_TEST_CHANNEL_ROOM={allgemein}")
print(f"IPHONEBLOG_TEST_CHANNEL_THREAD='{thread}'")
print(f"IPHONEBLOG_TEST_ARTICLE_ROOT='{root}'")
