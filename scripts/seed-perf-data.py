#!/usr/bin/env python3
"""Fill the test homeserver with a lived-in history for the performance tests.

    scripts/seed-perf-data.py            (after scripts/test-homeserver.sh start)

Adds six writers to #one-Chat (`Allgemein` on the test server) and the Blog room, then writes:

- #one-Chat: 160 messages, a third of them formatted (bold, links, lists, quotes), 30 photos in
  four sizes up to 4032x3024 (an iPhone photo, the decode that hurts), replies and reactions;
- a long thread in #one-Chat, 90 replies with 12 photos, under a root the tests find by its
  sender ("Perf Thread");
- the Blog article's thread (the Diskussion), 90 replies.

Writes the ids the tests need to build/perf-data.env. Standard library only; the photos are
PNGs drawn here, so nothing is downloaded. docs/performance.md.
"""
import hashlib
import hmac
import json
import os
import random
import struct
import sys
import urllib.parse
import urllib.request
import zlib

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(HERE, "build")
URL = None  # from build/perf-homeserver.env, never a default: other test servers share this Mac
random.seed(120)


def read_env(path):
    env = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                env[k] = v.strip("'")
    return env


def call(method, path, token=None, body=None, raw=None, content_type="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(URL + path, data=data, method=method)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b"{}")


def shared_secret():
    with open(os.path.join(BUILD, "perf-synapse", "homeserver.yaml")) as f:
        for line in f:
            if line.startswith("registration_shared_secret:"):
                return line.split(":", 1)[1].strip().strip('"')
    sys.exit("seed-perf-data: no registration_shared_secret in build/synapse/homeserver.yaml")


def register(name, display):
    """Synapse's shared-secret registration: no rate limit, no admin."""
    secret = shared_secret()
    nonce = call("GET", "/_synapse/admin/v1/register")["nonce"]
    password = os.urandom(12).hex()
    mac = hmac.new(secret.encode(), digestmod=hashlib.sha1)
    mac.update(b"\x00".join([nonce.encode(), name.encode(), password.encode(), b"notadmin"]))
    out = call("POST", "/_synapse/admin/v1/register", body={
        "nonce": nonce, "username": name, "password": password, "admin": False, "mac": mac.hexdigest()})
    token = out["access_token"]
    call("PUT", f"/_matrix/client/v3/profile/{urllib.parse.quote(out['user_id'])}/displayname", token,
         {"displayname": display})
    return token


def png(width, height, seed):
    """A photo-sized PNG: one gradient row per band of 48 rows, each row shifted. Small to upload,
    but it decodes to the full width x height like a photo does, which is the cost we measure."""
    r0, g0, b0 = (seed * 53) % 256, (seed * 97) % 256, (seed * 151) % 256
    rows = []
    for band in range(0, height, 48):
        fy = band * 255 // max(1, height - 1)
        base = bytearray(width * 3)
        for x in range(width):
            base[3 * x] = (r0 + x * 255 // width) % 256
            base[3 * x + 1] = (g0 + fy) % 256
            base[3 * x + 2] = (b0 + (x ^ band) % 97) % 256
        base = bytes(base)
        for y in range(band, min(band + 48, height)):
            k = (y * 3 * 7) % len(base)
            rows.append(b"\x00" + base[k:] + base[:k])
    raw = b"".join(rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


SIZES = [(4032, 3024), (3024, 4032), (1920, 1080), (1200, 900)]
_media = {}


def photo(token, n):
    """Uploads (once per size and colour) and returns the content of an m.image."""
    w, h = SIZES[n % len(SIZES)]
    key = (w, h, n % 6)
    if key not in _media:
        data = png(w, h, n % 6)
        up = call("POST", "/_matrix/media/v3/upload?filename=foto.png", token, raw=data, content_type="image/png")
        _media[key] = (up["content_uri"], len(data))
    uri, size = _media[key]
    return {"msgtype": "m.image", "body": f"IMG_{4000 + n}.png", "url": uri,
            "info": {"w": w, "h": h, "mimetype": "image/png", "size": size}}


WORDS = ("iPad mini iPhone Kamera Akku Display ProMotion Shortcuts Mac Studio Vision Pro Widgets "
         "Kurzbefehle Lightroom Fotos Podcast Folge Update Beta Ladegerät MagSafe Hülle Tastatur").split()


def sentence(n):
    return " ".join(random.choice(WORDS) for _ in range(n)).capitalize() + "."


def text(n):
    kind = n % 6
    if kind == 0:
        body = sentence(6)
        return {"msgtype": "m.text", "body": body}
    if kind == 1:
        body = " ".join(sentence(random.randint(8, 16)) for _ in range(4))
        return {"msgtype": "m.text", "body": body}
    if kind == 2:
        plain = f"**{sentence(3)}** {sentence(10)} https://www.iphoneblog.de/test-{n}/"
        html = (f"<strong>{sentence(3)}</strong> {sentence(10)} "
                f"<a href=\"https://www.iphoneblog.de/test-{n}/\">iphoneblog.de/test-{n}</a>")
        return {"msgtype": "m.text", "body": plain, "format": "org.matrix.custom.html", "formatted_body": html}
    if kind == 3:
        items = "".join(f"<li>{sentence(4)}</li>" for _ in range(4))
        return {"msgtype": "m.text", "body": "- a\n- b\n- c\n- d", "format": "org.matrix.custom.html",
                "formatted_body": f"<p>{sentence(5)}</p><ul>{items}</ul>"}
    if kind == 4:
        return {"msgtype": "m.text", "body": f"> {sentence(8)}\n\n{sentence(6)}", "format": "org.matrix.custom.html",
                "formatted_body": f"<blockquote>{sentence(8)}</blockquote><p>{sentence(6)} <em>{sentence(2)}</em> <code>xcrun simctl</code></p>"}
    return {"msgtype": "m.text", "body": sentence(random.randint(2, 5))}


def main():
    global URL
    env = read_env(os.path.join(BUILD, "perf-homeserver.env"))
    URL = env["IPHONEBLOG_TEST_HOMESERVER"]
    channel = env["IPHONEBLOG_TEST_CHANNEL_ROOM"]
    article_root = env["IPHONEBLOG_TEST_ARTICLE_ROOT"]
    blog = call("GET", "/_matrix/client/v3/directory/room/" + urllib.parse.quote("#blog:localhost"))["room_id"]

    names = ["Anna K.", "Ben M.", "Clara S.", "David R.", "Eva W.", "Felix H."]
    writers = [register(f"perf{i}", n) for i, n in enumerate(names)]
    for t in writers:
        call("POST", f"/_matrix/client/v3/join/{urllib.parse.quote(channel)}", t, {})
        call("POST", f"/_matrix/client/v3/join/{urllib.parse.quote(blog)}", t, {})
    threader = register("perfthread", "Perf Thread")
    call("POST", f"/_matrix/client/v3/join/{urllib.parse.quote(channel)}", threader, {})

    txn = [0]

    def send(room, token, content, kind="m.room.message"):
        txn[0] += 1
        return call("PUT", f"/_matrix/client/v3/rooms/{urllib.parse.quote(room)}/send/{kind}/p{txn[0]}",
                    token, content)["event_id"]

    # The long thread's root ten messages above the newest, so the thread tests find its
    # "90 Antworten" after a short scroll; 150 messages sit above it.
    thread_root = None
    ids = []
    for n in range(160):
        if n == 150:
            thread_root = send(channel, threader, {"msgtype": "m.text", "body": "Der lange Thread für die Messung"})
        t = writers[n % len(writers)]
        content = photo(t, n) if n % 5 == 2 and len(ids) < 200 else text(n)
        if n % 11 == 7 and ids:
            content["m.relates_to"] = {"m.in_reply_to": {"event_id": random.choice(ids[-20:])}}
        ids.append(send(channel, t, content))
        if n % 9 == 4:
            send(channel, writers[(n + 1) % len(writers)],
                 {"m.relates_to": {"rel_type": "m.annotation", "event_id": ids[-1], "key": random.choice("👍❤️😂🎉")}},
                 "m.reaction")
    for n in range(90):
        t = writers[n % len(writers)]
        content = photo(t, n + 7) if n % 8 == 3 else text(n)
        content["m.relates_to"] = {"rel_type": "m.thread", "event_id": thread_root, "is_falling_back": True,
                                   "m.in_reply_to": {"event_id": thread_root}}
        send(channel, t, content)
    for n in range(90):
        t = writers[n % len(writers)]
        content = text(n)
        content["m.relates_to"] = {"rel_type": "m.thread", "event_id": article_root, "is_falling_back": True,
                                   "m.in_reply_to": {"event_id": article_root}}
        send(blog, t, content)

    with open(os.path.join(BUILD, "perf-data.env"), "w") as f:
        f.write(f"IPHONEBLOG_PERF_THREAD_ROOT='{thread_root}'\n")
        f.write("IPHONEBLOG_PERF_THREAD_SENDER='Perf Thread'\n")
        f.write(f"IPHONEBLOG_PERF_CHANNEL_MESSAGES=160\n")
    print(f"seed-perf-data: 160 messages ({len(_media)} photos uploaded), two threads of 90 replies")


if __name__ == "__main__":
    main()
