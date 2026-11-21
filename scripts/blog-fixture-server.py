#!/usr/bin/env python3
"""A stand-in for the blog and its API for the UI tests (Tests/UITests).

    scripts/blog-fixture-server.py <port> [root-event-id]

/blog/          a long app-view page: twelve articles, each with its "Diskussion" link
/api/links.json the threads that exist (articles 2 and 6 have one)
/api/threads/<root>.json
/article-thread POST as on chat.iphoneblog.de (2026-11-14_interfaces.md): 401 without a token;
                with one, the first call for article 1 makes its thread, later calls return
                the same root with created=false. <root-event-id> is that thread's root, the
                test server's article root when the member test runs.
/calls          how many article-thread calls made a thread and how many found one, how often the
                blog page loaded, and the staff-gate counts below
/video/fx1/      an article video for article 2's card: manifest.json, h264.mp4 (the app's
                sample, with byte ranges as AVPlayer asks) and captions.de.vtt (blog-card-video.md)
/gate/start?rd= a stand-in for beta's staff gate: sets its session cookie and redirects to rd
/gate/reset     POST: a new session token, so every earlier cookie is void
/wp-json/iphoneblog/v1/one/episodes
                the bundled episodes with the gate's cookie; without it 302 to /gate/start,
                as the real gate answers (BlogLoadUITests)
/_iphoneblog/v1/search
                the search API of ADR-0010 (SiteSearchUITests, testScrollSearch): 60 mixed hits
                for any query of two letters or more, chat only with a token, none for "nichts";
                each request is counted in /calls ("search")
/20…/           an article page, as a search hit opens it; counted in /calls ("article_loads")
"""
import html, json, os, secrets, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[1])
new_root = sys.argv[2] if len(sys.argv) > 2 else "$madebypost"
ARTICLES = [(i, f"https://www.iphoneblog.de/2026/11/{16 - i:02d}/artikel-{i}/", f"Artikel {i}") for i in range(1, 13)]
ARTICLES[0] = (1, "https://www.iphoneblog.de/2023/02/28/tipp-in-der-reader-darstellung-verschickt-apple-mail-einen-kompletten-web-artikel/", "Artikel 1")
EXISTING = {ARTICLES[1][1]: "$existing", ARTICLES[5][1]: "$existing6"}
made = {}
calls = {"created": 0, "found": 0, "blog_loads": 0, "gate_starts": 0, "episodes_ok": 0, "episodes_gated": 0}
gate = {"token": secrets.token_hex(16)}
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Fixtures")
EPISODES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Fixtures", "episodes-fixture.json")

def page():
    body = []
    for i, link, title in ARTICLES:
        href = "iphoneblog-chat://diskussion?url=" + urllib.parse.quote(link, safe="")
        text = " ".join(["Ein Absatz Text, damit die Seite lang wird."] * 12)
        body.append(f'<article><h2>{html.escape(title)}</h2><p>{text}</p>'
                    f'<p class="post__discussion"><a data-app-discussion href="{href}">Diskussion {i}</a></p></article>')
    return ('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
            '<style>body{font:17px -apple-system;margin:16px}@media(prefers-color-scheme:dark){body{background:#111;color:#eee}}'
            'a{color:#0f7d78}</style></head><body class="app-view">' + "".join(body) + "</body></html>")

SEARCH_KINDS = ["post", "video", "link", "discussion", "one", "post", "chat", "video", "post", "link"]
LABELS = {"post": "Beitrag", "one": "#one", "video": "Video", "link": "Link", "chat": "Chat", "discussion": "Diskussion"}

def search_hits(q, signed_in):
    """60 hits of every kind, as search-api answers them; the query is marked in each snippet."""
    word = html.escape(q)
    hits = []
    for i in range(60):
        kind = SEARCH_KINDS[i % len(SEARCH_KINDS)]
        if kind == "chat" and not signed_in:
            continue
        n = i + 1
        url = f"https://www.iphoneblog.de/2026/11/{(n % 28) + 1:02d}/{kind}-{n}/"
        hit = {"id": f"{kind}:{n}", "type": kind, "label": LABELS[kind], "title": f"{LABELS[kind]} {n} über {word}",
               "snippet": f"… und dann hält der <mark>{word}</mark> jetzt zwei Tage, sagt Nummer {n} &amp; noch "
                          f"ein Satz dazu, damit die Zeile umbricht und der <mark>{word}</mark> zweimal vorkommt …",
               "url": url, "deep_link": url, "t": None, "room_id": None, "event_id": None, "thread_root": None,
               "room_name": None, "sender_name": None, "domain": None, "mentions": None, "post_id": 60000 + n,
               "published": f"2026-11-{(n % 20) + 1:02d}T12:00:00Z", "score": round(1 - n / 100, 3)}
        if kind == "video":
            hit.update({"t": 60 * n + 14, "deep_link": url + f"?t={60 * n + 14}"})
        elif kind == "link":
            hit.update({"title": f"Apple-Seite {n} zu {word}", "url": f"https://www.apple.com/de/{word}-{n}/",
                        "deep_link": f"https://www.apple.com/de/{word}-{n}/", "domain": "apple.com", "mentions": 3, "post_id": None})
        elif kind == "discussion":
            hit.update({"title": f"„Artikel 2“", "sender_name": "Jana Sommer", "event_id": f"$reply{n}",
                        "thread_root": "$existing", "deep_link": f"https://chat.iphoneblog.de/#/room/!blog/$reply{n}"})
        elif kind == "chat":
            hit.update({"title": "", "sender_name": "Philip", "room_name": "one-chat", "room_id": "!fixture:iphoneblog.de",
                        "event_id": f"$chat{n}", "deep_link": f"https://chat.iphoneblog.de/#/room/!fixture/$chat{n}", "post_id": None})
        elif kind == "one" and not signed_in:
            hit["locked"] = True
        hits.append(hit)
    return hits

def search(query, headers):
    params = urllib.parse.parse_qs(query)
    q = params.get("q", [""])[0].strip()
    types = [t for t in params.get("types", [""])[0].split(",") if t]
    page, limit = int(params.get("page", ["1"])[0]), int(params.get("limit", ["20"])[0])
    signed_in = headers.get("Authorization", "").startswith("Bearer ")
    calls.setdefault("search", []).append({"q": q, "types": types, "page": page, "auth": signed_in})
    if not 1 <= len(q) <= 200 or not 1 <= page <= 5 or not 1 <= limit <= 20:
        return 400, {"code": "search_query"}
    hits = [] if q.lower() == "nichts" or len(q) < 2 else search_hits(q, signed_in)
    counts = {k: sum(1 for h in hits if h["type"] == k) for k in LABELS}
    if types:
        hits = [h for h in hits if h["type"] in types]
    return 200, {"q": q, "page": page, "total": len(hits), "counts": counts, "took_ms": 3,
                 "hits": hits[(page - 1) * limit:page * limit]}

def article(path):
    return ('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>'
            f'<body class="app-view"><article><h1>Artikel unter {html.escape(path)}</h1><p>Text.</p></article></body></html>')

def thread(root):
    title = next((t for _, l, t in ARTICLES if EXISTING.get(l) == root or made.get(l) == root), "Artikel")
    replies = [] if root == new_root else [{"event_id": "$r1", "ts": 1763290000000, "sender_name": "Jana Sommer", "body": "Guter Punkt."}]
    # Article 2's card has a video (blog-card-video.md); the others have none.
    video, link = None, None
    if root == "$existing":
        base = f"http://127.0.0.1:{port}/video/fx1/"
        video = {"id": "fx1", "manifest_url": base + "manifest.json", "poster_url": None,
                 "captions_url": base + "captions.de.vtt", "duration_ms": 10000, "width": 1280, "height": 720}
        link = ARTICLES[1][1]
    return {"root": {"root_event_id": root, "title": title, "link": link, "image_url": None, "teaser": None,
                     "published_ts": 1763290000000, "reply_count": len(replies), "latest_reply_ts": None,
                     "last_repliers": [], "video": video}, "replies": replies, "next": None}

class Handler(BaseHTTPRequestHandler):
    def send(self, status, body, kind="application/json", headers=()):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(parsed.path)
        if path.startswith("/blog"):
            calls["blog_loads"] += 1
            return self.send(200, page(), "text/html; charset=utf-8")
        if path == "/gate/start":
            calls["gate_starts"] += 1
            target = urllib.parse.parse_qs(parsed.query).get("rd", ["/blog/?app=1"])[0]
            return self.send(302, "", "text/plain", [("Location", target), ("Set-Cookie", f"fixture_gate={gate['token']}; Path=/")])
        if path == "/wp-json/iphoneblog/v1/one/episodes":
            if f"fixture_gate={gate['token']}" in self.headers.get("Cookie", ""):
                calls["episodes_ok"] += 1
                with open(EPISODES, encoding="utf-8") as fixture:
                    return self.send(200, fixture.read())
            calls["episodes_gated"] += 1
            return self.send(302, "", "text/plain", [("Location", "/gate/start?rd=" + urllib.parse.quote(self.path, safe=""))])
        if path == "/_iphoneblog/v1/search":
            status, answer = search(parsed.query, self.headers)
            return self.send(status, answer)
        if path.startswith("/20"):
            calls.setdefault("article_loads", []).append(self.path)
            return self.send(200, article(path), "text/html; charset=utf-8")
        if path == "/api/links.json":
            return self.send(200, {"generated_ts": 0, "links": {**EXISTING, **made}})
        if path.startswith("/api/threads/") and path.endswith(".json"):
            root = path[len("/api/threads/"):-5]
            known = set(EXISTING.values()) | set(made.values())
            return self.send(200, thread(root)) if root in known else self.send(404, {})
        if path == "/video/fx1/manifest.json":
            return self.send(200, {"files": [{"name": "h264.mp4", "codecs": "avc1.640028", "width": 1280, "height": 720,
                                              "media": None, "list": True}]})
        if path == "/video/fx1/captions.de.vtt":
            with open(os.path.join(FIXTURES, "sample-captions.de.vtt"), encoding="utf-8") as vtt:
                return self.send(200, vtt.read(), "text/vtt; charset=utf-8")
        if path == "/video/fx1/h264.mp4":
            calls["card_video_plays"] = calls.get("card_video_plays", 0) + 1
            return self.send_file(os.path.join(FIXTURES, "sample-video.mp4"), "video/mp4")
        if path == "/calls":
            return self.send(200, calls)
        self.send(404, {})

    def send_file(self, path, kind):
        """A file with byte ranges, as AVPlayer reads a video."""
        with open(path, "rb") as f:
            data = f.read()
        start, end = 0, len(data) - 1
        ranged = self.headers.get("Range", "")
        if ranged.startswith("bytes="):
            first, _, last = ranged[6:].partition("-")
            start = int(first) if first else 0
            end = min(int(last), len(data) - 1) if last else len(data) - 1
        chunk = data[start:end + 1]
        self.send_response(206 if ranged else 200)
        self.send_header("Content-Type", kind)
        self.send_header("Accept-Ranges", "bytes")
        if ranged:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.send_header("Content-Length", str(len(chunk)))
        self.end_headers()
        self.wfile.write(chunk)

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path == "/gate/reset":
            gate["token"] = secrets.token_hex(16)
            return self.send(200, {})
        if urllib.parse.urlparse(self.path).path != "/article-thread":
            return self.send(404, {})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if not self.headers.get("Authorization", "").startswith("Bearer "):
            return self.send(401, {"errcode": "M_MISSING_TOKEN", "error": "a Matrix access token is needed"})
        url = body.get("url", "")
        if url in EXISTING:
            calls["found"] += 1
            return self.send(200, {"root_event_id": EXISTING[url], "created": False})
        if url != ARTICLES[0][1]:
            return self.send(404, {"errcode": "M_NOT_FOUND", "error": "no published post"})
        created = url not in made
        made[url] = new_root
        calls["created" if created else "found"] += 1
        self.send(200, {"post_id": 43432, "link": url, "room_id": "!blog", "root_event_id": new_root, "created": created})

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
