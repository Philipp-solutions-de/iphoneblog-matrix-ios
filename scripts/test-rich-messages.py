#!/usr/bin/env python3
"""Seeds the test homeserver with one message of every rich kind the app must show.

Usage: test-rich-messages.py <homeserver url> <access token> <room id> [<thread root>]

Without a thread root the messages go to the room's timeline (a #one-Chat channel); with one
they go into that thread (an article's Diskussion). The set: formatted text, a plain link, a
reply that quotes the formatted message, an image, a video and a PDF. Media come from
scripts/fixtures/. Prints nothing; fails loudly.
"""

import json
import pathlib
import sys
import urllib.parse
import urllib.request
import uuid

FIXTURES = pathlib.Path(__file__).parent / "fixtures"


def request(url, token, method="GET", body=None, content_type="application/json"):
    data = body if isinstance(body, bytes) or body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def main():
    base, token, room = sys.argv[1:4]
    root = sys.argv[4] if len(sys.argv) > 4 else None

    def send(content):
        if root:
            relation = content.setdefault("m.relates_to", {})
            relation.update({"rel_type": "m.thread", "event_id": root})
            relation.setdefault("is_falling_back", "m.in_reply_to" not in relation)
            if relation["is_falling_back"]:
                relation["m.in_reply_to"] = {"event_id": root}
        path = f"/_matrix/client/v3/rooms/{urllib.parse.quote(room)}/send/m.room.message/{uuid.uuid4().hex}"
        return request(base + path, token, "PUT", content)["event_id"]

    def upload(name, mimetype):
        data = (FIXTURES / name).read_bytes()
        url = f"{base}/_matrix/media/v3/upload?filename={urllib.parse.quote(name)}"
        return request(url, token, "POST", data, mimetype)["content_uri"], len(data)

    formatted = send({
        "msgtype": "m.text",
        "body": "**Fett**, *kursiv* und `Code`\n\n- eins\n- zwei\n\n> Ein Zitat",
        "format": "org.matrix.custom.html",
        "formatted_body": "<strong>Fett</strong>, <em>kursiv</em> und <code>Code</code>"
                          "<ul><li>eins</li><li>zwei</li></ul><blockquote>Ein Zitat</blockquote>",
    })
    send({"msgtype": "m.text", "body": "Lies das: https://www.iphoneblog.de/"})
    send({
        "msgtype": "m.text",
        "body": "> <@writer:localhost> Fett, kursiv und Code\n\nDie Antwort zitiert.",
        "m.relates_to": {"m.in_reply_to": {"event_id": formatted}},
    })

    image, size = upload("bild.png", "image/png")
    send({"msgtype": "m.image", "body": "bild.png", "url": image,
          "info": {"mimetype": "image/png", "size": size, "w": 640, "h": 400}})
    video, size = upload("video.mp4", "video/mp4")
    send({"msgtype": "m.video", "body": "video.mp4", "url": video,
          "info": {"mimetype": "video/mp4", "size": size, "w": 320, "h": 200, "duration": 2000}})
    pdf, size = upload("dokument.pdf", "application/pdf")
    send({"msgtype": "m.file", "body": "dokument.pdf", "url": pdf,
          "info": {"mimetype": "application/pdf", "size": size}})


if __name__ == "__main__":
    main()
