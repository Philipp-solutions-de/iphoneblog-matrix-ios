# Architecture

The iphoneblog chat app is our own SwiftUI app on the Matrix engine (matrix-rust-sdk).
It does what a community needs: channels, threads, direct messages, mentions, images and
reactions. It has no calls, no spaces and no encryption screens. One codebase serves iPhone,
iPad and Apple-silicon Macs.

## The pieces

```
 iPhone / iPad / Mac                                   alex (behind edge)
 ┌───────────────────────────────┐                     ┌───────────────────────────┐
 │ SwiftUI screens               │                     │ chat.iphoneblog.de        │
 │   AppModel (signed out / in)  │  sliding sync, REST │   Synapse, server name    │
 │   ChatSession → RoomListModel │ ──────────────────► │   iphoneblog.de           │
 │                 → Timeline    │                     │   /_matrix/push → Sygnal  │
 │ MatrixRustSDK (pinned)        │                     ├───────────────────────────┤
 │   sqlite store per account    │  OAuth 2.0 + PKCE   │ auth.iphoneblog.de (MAS)  │
 │ Keychain: session, tokens     │ ──────────────────► │   upstream: WordPress     │
 ├───────────────────────────────┤                     │   OpenID Connect          │
 │ Notification service ext.     │ ◄── APNs ◄── Sygnal └───────────────────────────┘
 │   fetches the event, writes   │
 │   "Name in #channel: text"    │
 └───────────────────────────────┘
```

## Decisions

**SwiftUI, iOS 18.5 and later.** One view tree for iPhone and iPad: `NavigationSplitView`
gives the iPad a channel column beside the conversation, and the iPhone a stack. The same
build runs on Apple-silicon Macs as an iPad app ("Designed for iPad"); no Mac-specific work.
iOS 18 covers every iPhone from the XS on, the same set as iOS 17; ChatKit (below) needs 18.5.

**The Matrix engine as a pinned Swift package.** `matrix-rust-components-swift`, the same
binding Element X uses, pinned with `exactVersion` in `project.yml`. The SDK does sync,
the room list, timelines, threads, media, sending queues and token refresh; the app does
screens. We keep our own code thin around it: `MatrixClientFactory` builds every client the
same way, `ChatSession` owns sync, `RoomListModel` turns the SDK's list diffs into rows.

**Preset server, no discovery.** The client talks to `https://chat.iphoneblog.de`
directly; people are `@name:iphoneblog.de`. No `.well-known/matrix` on the blog is needed.
Members never see a server field.

**Sign-in through the blog.** The app registers itself with the Matrix Authentication
Service at `auth.iphoneblog.de` as one static client (`OAUTH_CLIENT_ID` in brand.env; WordPress's
web-login accepts only that client's tokens; empty, as on test servers, means dynamic
registration), opens the sign-in page in
`ASWebAuthenticationSession`, and MAS sends the member on to WordPress. The callback uses the
custom scheme `de.iphoneblog.chat:/oauth/callback` with the client URI
`https://chat.iphoneblog.de/app`; MAS accepts a custom scheme when it is the reverse of the
client URI's host, so no apple-app-site-association file is needed for sign-in. The app also
answers the old scheme `de.iphoneblog.matrix`, so a client registered while `matrix.iphoneblog.de`
was the host keeps signing in for as long as that alias lives. The web sheet shares Safari's cookies: someone signed in to the
blog taps once. Tokens live in the keychain; the SDK refreshes them and hands new ones to
`KeychainSessionDelegate`.

**No encryption.** Rooms and direct messages are unencrypted (Thorsten's decision). The app
builds every client with cross-signing and key backup switched off and never creates an
encrypted room. A second or third device signs in and sees all history at once; there is no
"confirm your identity" step. Synapse sets
`encryption_enabled_by_default_for_room_type: off`.

**Sliding sync.** Synapse's native simplified sliding sync (MSC4186, on by default). The
room list loads in one round trip whatever the number of rooms.

**Push through our own Sygnal.** The app registers a pusher with app id
`<BUNDLE_ID>.ios.prod` (today `de.iphoneblog.matrix.preview.ios.prod`, Thorsten's team; see apple-setup.md) and the gateway `https://chat.iphoneblog.de/_matrix/push/v1/notify`.
A notification service extension (second target, shared app group) receives each push,
fetches the event with the SDK's notification client and writes "Name in #channel: text".
A tap opens the channel or the thread. Unencrypted rooms make this simple: no keys to share
with the extension. Apple's notification-filtering entitlement is requested for Alex's
account so the extension may drop pushes it cannot show.

**Four tabs for members, two for everyone else; the blog as the front page.** #one members see
Blog, #one, Für dich and Ich (Thorsten, 2026-11-17); the #one tab shows one "#", its big symbol,
over the label "one" (Thorsten, 2026-11-20). Everyone else sees Blog and #one: signed out, a neutral
sign-in ("Der Chat für #one-Mitglieder", Anmelden); signed in without #one, "Nur für
#one-Mitglieder" with Abmelden and Konto löschen (App Store 5.1.1(v), since they have no Ich).
No price, no way to buy, no hint where to get #one; they read discussions without writing
(Thorsten, 2026-11-16). The tabs follow membership as it changes (`Router.isMember`). For
members, #one shows the #one rooms (`GET /_iphoneblog/v1/rooms`, else the space #one's
children) in its room bar. every visual value lives in `App/Sources/Theme.swift`, light and
dark by the system. The Blog tab is a `WKWebView` on WordPress's app view (`?app=1`, which
drops banner, header, menu and footer), not native article cards: the blog renders articles,
paywall included, exactly as the site does, and the app adds only the discussion. The web
view routes taps only: a "Diskussion" link opens the native discussion, a link to the blog
keeps `app=1`, any other site opens in Safari. Redirects and the page's own loads go where the
server sends them, so beta's staff gate (Authelia at `auth.phso.de`) signs in inside the view.
One web view lives as long as the app (`AppModel.blogWeb`): a tab switch, a sign-in or a
discussion never reloads the page the reader is on. It belongs to `AppModel`, not to the tab,
because the root builds a new tab bar when the sign-in state changes; a web view per tab bar
loaded the blog several times at once and raced at beta's gate (Philip's 500, 2026-11-20).
The hub's episode request (`LiveEpisodesSource`) carries that web view's cookies for the blog's
host, so the gate session on beta, and never follows a redirect: without a session the gate's
302 means no episodes, not a sign-in started outside the web view. The discussion uses the system back
button, so a swipe from the left edge returns to the blog where the reader was; a custom back
button would switch that swipe off (Thorsten's test of build 70). The Blog home and #one's
start screen keep a navigation bar too, with their own header in it (the logo; "#one" and the search):
with the bar hidden on one side of a push, the back button rode with the page and jumped when a
back swipe was let go (Philip, 2026-11-20).

**An article's video plays in its card** (Thorsten, 2026-11-20; the field in the WordPress repo's
blog-card-video.md). The discussion's header shows the poster (the card's image without one)
with play; a tap plays it right there with the episode player (`EpisodePlayer`, PiP, captions
drawn). The captions start off and "CC" under the video turns them on; the choice is kept on the
device for the next card video (Thorsten, 2026-11-21: "CC sollen default off sein und brauchen
einen toggle"). The rendition is picked from the manifest when playing starts: the smallest listed
file at least as wide as the screen, `h264.mp4` without a manifest. The title opens the article.
The video comes from the thread file, which carries the backfilled cards' too, so no Matrix edit
is read (`CardVideo.swift`).

**Every article has a thread when someone signed in opens it.** A signed-in tap on
"Diskussion" calls `POST /_iphoneblog/v1/article-thread` with the article's www address and
the Matrix token; the server makes the thread if there is none (idempotent per post) and the
app opens the root it returns. The call needs a token, so nobody can make the bot post a
thread per article from outside. Signed out, the app reads the static files the article bot
writes (`links.json` maps an article URL to its thread, matched by the decoded, lower-case path
with one trailing slash, so `www` and `beta` find the same one; `threads/<root>.json` holds the
replies). An article nobody has opened yet shows "Noch keine Antworten" and "Anmelden, um
mitzudiskutieren", never an empty screen; links.json lists a new thread within a minute.
#one members get the conversation views and write in the thread; the reply count under the
thread's first message counts the live replies, so the header shows the file's count to
readers only (it lags by up to a minute). Readers see each reply's `formatted_body`, which
the server sanitizes with the website's allowlist (`ReplyHTML`, no WebKit), or else its
`body` with its markdown and every address linked (`ReplyText`), and a picture from `media`
(the server's public copy, EXIF stripped; a tap opens the full size). Files and videos show
their body text ("in der App zu sehen"); reply quotes and link previews are not in the files. `scripts/build.sh ui` drives this path in the simulator
against `scripts/blog-fixture-server.py`, and `RichMessagesUITests` checks formatting, links,
replies, pictures, video, files and the composer against the test homeserver.

**#one opens on draft B** (Thorsten, 2026-11-20, replacing the hub of 2026-11-18): "Videos"
with "Alle" and the newest episodes as a cover flow (the centred one full size, its neighbours
smaller and turned; flat with Reduce Motion), then "Räume": a Threads row with the latest
thread and the unread ones counted, and every #one room with its last sender, line, time and
unread count (`OneHubView.swift`). An episode opens its page, Threads the list, a room the Chat
screen below on that room. Without episodes from the route the rooms show alone.

**#one: a room bar, variant A.** Under the title "#one" (with the open room's topic) a bar of
chips holds every #one room from the server, each with its unread count, "@" for a mention and
99+ as the cap; tap only, no swipe; a teal dot at the bar's edge marks a room with news out of
sight. The open room sits under the bar and shows no title of its own; the tab opens the last
room read (`Router.currentRoomID`, forgotten on sign-out). The bar's counts and dots are the
way to the next room with news; there is no "Weiter" bar over the room (Thorsten, 2026-11-20).
Above the first unread message a teal
"Neu" divider; when it is out of sight a pill "n neue · zur ersten springen" jumps to it, as on
the web. Bots the server lists (`GET /_iphoneblog/v1/bots`) get their name in the strong teal
and a "Bot" pill with a robot, never by name. A room where members may not post (power levels, as on the
server's read-only #releases) shows "Nur das Team schreibt hier" in place of the composer;
reactions stay open.

**Für dich: what concerns me, in one list.** Mentions of me (@me, @room, replies to my
messages), threads I take part in with new replies (#one and the Blog's discussions), and the
#one rooms with unread messages on top of "Alles"; "Alles · Erwähnungen · Threads"; newest
first; rows with the sender's picture and plain previews (`MemberAvatar`, `PushText.plain`). "Alle
gelesen" clears exactly what the filter shows; a long press on the tab clears everything, with a
haptic, while the badge shows something. Threads come from ChatKit's thread lists
(`ChatKitSession.involvedThreads`); their "new" is per device, like the Threads list was.

**Threads work as in Slack.** Under a message with replies, a row shows up to three repliers,
"n Antworten" in teal and when the last reply came; unread replies make it bold with a dot. A
tap on a message opens its thread, also to start one (links, mentions and pictures keep their
own tap), and the long-press menu offers "Im Thread antworten" first. Für dich › Threads lists the threads you started or wrote in, newest first, with an unread dot
for news. Counts come from the server's thread relations (`ChatThreadActivity`): the SDK's
timeline summary and thread list counted 3 and 9 for a thread with 6 replies. Unread is per
device (`ChatThreadSeen`). Not built: "Auch an #one senden" (Matrix has no event that is
both a thread reply and a channel message; it would take two events), push for replies in
threads you are in without a mention (Synapse sends none), and thread rows in the Blog tab,
which shows the website.

**A token error is checked before it signs anyone out.** MAS's access tokens live minutes;
the SDK refreshes them, our own HTTP calls do not, and when the SDK's refresh hits a restarting
MAS (502, 503, reset, timeout) it reports the same "unknown token" as a revoked session. So
`AuthGuard` checks every such report: one SDK request (refreshing on the way), then whoami. The
session ends only when MAS refuses the refresh token (invalid_grant) or the server refuses the
token three times in a row while MAS answers; anything else keeps the session and checks again
after 2, 4, 8 … 60 s. Our own calls retry once after a successful check. Concurrent errors
share one check, so at most one refresh; a 401 for a request sent before the latest refresh,
and refusals counted before it, never count. The app restores its session once per process: a
second restore after iOS rebuilt the scene ran two clients that refreshed the same token 45 ms
apart, which MAS treats as reuse and answers by revoking the session (Alex's logouts,
2026-11-17).
**The Neu divider.** A room shows "Neu" above the first message after the reader's
`m.fully_read`, which moves only when the reader leaves the room (Shim `ChatScreens`,
`moveFullyRead`). The SDK draws its read marker only when that event came with the room's first
events (about 20), so a reader with more unread, or a room the app had cached before opening,
got no divider (measured 2026-11-21: 30 new messages, no divider in 6 of 8 local attempts and
every CI attempt). The timeline controller therefore places the divider itself when the SDK sent
none: after the read-position event, once it is loaded and a message from someone else follows
(patch to `TimelineController`). Rejected: a larger room subscription window, which only moves
the limit.

**Mentions turn read when seen, "read up to here".** Opening a mention's thread or room marks
it read, without "Alle als gelesen": the timeline sends a read receipt for the newest message
on screen (Element X), and every mention up to it counts as read, in rooms and in threads
(Thorsten's decision A, 2026-11-17, as Element and the web chat do). Read or not comes from the
account's own receipts (`MentionsModel.withReadState`): a receipt of the mention's thread, or of
the room's timeline for a room message, or an unthreaded one, at an event no older than it.
Synapse's own `read` flag in /notifications is not used: it takes one receipt row per room,
whichever the database returns last, of any thread. "Alle als gelesen" sends one receipt per
thread and per room timeline on the newest listed mention, says when one fails, and reloads.

**A room read to its end also gets an unthreaded receipt.** The timelines send threaded
receipts only ("main" and one per thread), but the Rust SDK counts a room's unread messages from
the main and unthreaded receipts, so thread replies kept a room's badge at 1 while the server
had 0 (Alex's #entertainment, 2026-11-17). When the room's timeline has shown its newest
message, an unthreaded receipt goes on the room's newest event (`ChatSession+Receipts.swift`),
hidden ones included: a room push rule "notify" counts redactions, reactions and edits that no
timeline shows, so no receipt ever reached them (Philip's #bugs, 2026-11-18). The main receipt
follows to the newest of those the server files under "main" (never a thread's reaction, which
the server refuses). Neither passes a message or thread reply not yet seen, and the unthreaded
one waits while a thread mention in the room is unread, because it would mark that mention read. The badge
does not take the server's counts instead: they follow push rules, and the app turns
`.m.rule.message` off for members who want no message pushes.

**The timeline shows no one else's read receipts:** no avatars under the newest message and no
"Gelesen von" (Philip, 2026-11-20; the website shows none). The app's own receipts go out as
before, public: Element X ties both to `sharePresence`, so only the display is cut
(`TimelineViewModel`, patch).

**A thread opens only on its root.** A thread timeline built on a reply's ID sends receipts
naming that reply as the thread, and Synapse refuses each with 400 (Alex's #bugs, 2026-11-17).
`ResolvedThreadScreen` asks the server first and moves the route to the real root.

**Contact details go by mail, not into the chat.** A tap on a name, an avatar or a mention
opens the person's profile; a long press on a name or avatar opens "Kontaktdaten teilen" at
once. Members choose their email address (the blog account's, held by the server) and/or a phone
number typed each time, see who gets it and a warning, and confirm by name; the chat server
mails the recipient (`ContactShare`; contract in infra's docs/matrix.md, "Sharing contact
details"). Not offered with oneself or the room bot. A message with an email address or a
phone number asks first (`ChatContactWarning`); the server stores email addresses in messages
masked.

**Message links on our own domain.** "Link kopieren" copies
`https://chat.iphoneblog.de/#/<room>/$<event>`, where `<room>` is the room alias's localpart
(`one-chat`), else the percent-encoded room ID (`ChatLink`). The web chat at that address
copies and routes the same single form, so a link works without the app; with the app
installed, iOS hands it over as a universal link (`applinks:chat.iphoneblog.de`; the chat
server's apple-app-site-association names the app for `/` with a fragment). The link names no
thread: the opener reads the event and opens its thread if it replies in one, else the room
scrolled to the message, so a link stays right when a message moves into a thread. Signed out,
the web chat opens in a sheet. matrix.to links to rooms and messages open the same way. A
matrix.to link to a person (`matrix.to/#/@user:server`) opens their profile in the app, in a room
or a thread, never the browser (`ChatLink.userID`, `AppModel.open`); signed out it opens the
browser, since a profile needs a session. The thread screen does not yet scroll to the reply.

**Pushes for mentions, not for every message.** At an account's first sign-in the app turns the
default underride `.m.rule.message` off, once, marked in account data
(`de.iphoneblog.push_defaults`) so a later choice stays: every message then only counts towards
the badge, while @mentions (a reply to one's own message carries one) and new articles push.
Under Ich each #one room has "Alle / Nur Erwähnungen / Aus" as a room rule on top. Later: pushes
for replies in threads one takes part in need thread subscriptions (MSC4306), experimental and
off on the server.

**No direct messages.** The app offers no way to start one (a tap on a person opens nothing),
and direct rooms stay out of #one, Threads and Für dich; the server refuses to create
them (Thorsten, 2026-11-16).

**One search for blog and #one** (ADR-0010 in the WordPress repository, Thorsten 2026-11-21).
The magnifier in the Blog tab's bar and on the #one hub opens one search as a sheet:
`GET <homeserver>/_iphoneblog/v1/search` with the Matrix token when signed in, none when not; the
server decides from the token what the reader may see, the app keeps no rights of its own. It
searches as you type, 120 ms after the last keystroke, from two letters; a new keystroke
cancels the request in flight and drops its answer (`SiteSearchModel`). One mixed list in the
server's order, each hit with its type badge (coral only for #one, the colour rule), and the
chips Alle · Beiträge · Videos · Links · Chat with the server's counts; Chat holds the Blog's
discussions too. The snippet's `<mark>` becomes teal semibold text; the answer is decoded and
every row's text built off the main thread, so scrolling only lays out (`SiteSearchPage.prepare`,
`testScrollSearch`). A 401 refreshes the token once, then searches as anonymous. A tap closes
the sheet and opens the hit where it lives (`Router.target(for:chat:)`): a post or #one post in
the Blog tab's web view (www's address moved to the blog the tab shows), a video passage on the
episode's page playing from `t` (for #one members; others get the article at `?t=`), a chat
message in its room scrolled to it or its thread, a discussion reply in the article's discussion,
a link in Safari. The sheet keeps its query and hits for the next time it opens. Under a hit,
"und 3 weitere Antworten" (chat, discussion) or "und 1 weitere Stelle" (video) counts the other
matches in its group (`more`). In Alle a post merged with its own video and discussion carries
two teal lines, "Im Video ab 12:34" and "3 Antworten in der Diskussion"; each opens like a video
or discussion hit, the discussion by the article's root (`discussion.thread_root`).

**Search in a room is Matrix's own.** The magnifier in the open room sends `POST /_matrix/client/v3/search`
(room_events, in every #one room or, with the chip, only the open one; newest first,
`next_batch` paging); the rooms are
unencrypted, so Synapse can read them, and there is no index of our own. A hit shows sender,
time and the words marked; a thread reply opens its thread, a channel message scrolls the
channel to it (`ChatKitSession.focus`, Element X's focus on an event). Synapse stems in English
only, hard-coded in its source, so German inflections may not match; the empty state suggests
the word stem.

**Tab badges come from the server's counts.** The SDK counts a room's unread mentions in the
last few events it holds, so a mention with six or more messages after it dropped out. A room's
mention count is the larger of the SDK's and the server's notification list (the one Für dich
reads); `ChatSession` puts the #one and Für dich badges on `Router`, which `MainView`
observes. Für dich counts unread mentions and threads with news; unread room messages count on
#one. iOS 26's tab bar does not expose badges
to accessibility, so the sign-in test checks the counts and `BadgesUITests` keeps a screenshot.

**Members read #one articles in the Blog tab.** Once the page shows a blog page, a signed-in
app asks WordPress for a one-time sign-in address (`POST /wp-json/iphoneblog/v1/chat/web-login`
with the Matrix access token, iphoneblog-wordpress PR #276) and opens it; WordPress sets its
cookie (14 days, read-only) and returns to the page. The request is a `fetch` from inside the
web view, because on beta only the web view holds the staff gate's cookie, and it runs in its
own JavaScript world, so the blog's scripts never see the token. Asked once per app start and
person; a 401 refreshes the token and asks once more; a used link (410) asks once more. Only
tokens of the app's static MAS client count, so sign-in must use that fixed client id.
Signing out removes WordPress's cookies from the web view.

**Mentions from the server.** Für dich lists `GET /notifications?only=highlight`: the server
already decides what mentions me (read state: see "read up to here" above). The push switches
on Ich are server push rules for the same reason: "Neue Artikel" is an override rule
(`de.iphoneblog.new_articles`) on events in the Blog room that carry the bot's
`de.iphoneblog.article` field, while the Blog room itself stays on mentions only, so replies
under articles do not ring.

**Reuse before writing: the SDK's UI layer plus Element X's chat views.** The Matrix engine's
UI layer (`matrix-sdk-ui`, Apache-2.0, inside the Swift bindings) does the chat logic. For the
views we take Element X iOS's timeline, thread and composer code instead of writing our own
(decision 2026-11-14, from the reuse survey `2026-11-14_research-matrix-reuse.md`, option 1).
That code is AGPL-3.0, so this app is AGPL-3.0 too; the repository is public, as AGPL asks.

| Part | From matrix-sdk-ui | From Element X (transplanted, AGPL) | Our own code |
|---|---|---|---|
| Sync | `SyncService` | | start and stop with the app's life cycle |
| Room list | `RoomListService`, filters, diffs, unread and mention counts | | `RoomListModel`, the channel list view (our design) |
| Timeline | `Timeline`: pagination, local echo, send queue, edits, reactions, receipts | `Screens/Timeline` (cells, list, reactions, replies, thread summaries), `Services/Timeline` (SDK wrapper, view items) | adapters, our colours and type, cells we do not want removed; 16 pt between two messages of a group and above a new sender, 4 pt after a paragraph inside a message, a run of blank lines one paragraph, a `<br>` a line break without space (`Shim/ChatParagraphs.swift`, values shared with the web, chat-web PR #23); swipes on a message (`Shim/MessageSwipe.swift`): right opens the thread, left the menu with its reactions, across the whole row width (beside a short message too), never within 30 pt of the left edge, where swipe-back lives |
| Threads | thread focus, `ThreadListService`, thread subscriptions | `Screens/ThreadTimelineScreen`, `Screens/RoomThreadListScreen` | the article discussions and the threads in #one |
| Composer | send queue, replies, edits, `Mentions`, markdown to HTML, media upload | the composer, its formatting toolbar (+ › Textformatierung) and mention suggestions from `Screens/RoomScreen`, `Other/Pills` | no polls, no voice messages |
| Media | thumbnails, files, upload with progress | `Screens/FilePreviewScreen`, `Screens/MediaPickerScreen`, `Screens/MediaUploadPreviewScreen`; link previews through Apple's `LPMetadataProvider` (the phone fetches the page, not Synapse's preview_url) | the upload progress bar under a sending photo, video or file (`Shim/ChatUploadProgress.swift`); animated GIFs play from the original and go out unchanged (Element X), with Reduce Motion as their first frame (patch); with a caption, the picture alone gets the rounded corners, so the caption keeps its first letter (patch); Markieren in the upload preview draws on a photo, not a GIF, with PencilKit and sends the marked-up copy (`Shim/ChatMarkup.swift`); "GIFs aus dem Chat" in the + menu of #one rooms and threads, for members, never the Blog room: Beliebt, Neu and a search over the server's library of GIFs posted in #one (gif-library.md, `App/Sources/GIFs`); a tap sends an m.image with the library's mxc, no upload (`Shim/ChatGIFLibrary.swift`, `TimelineController.sendMessageEventContent` patch, behind the posting notice); a long press edits tags or reports; a GIF of one's own that is new to the library asks for tags above the caption, with on-device Vision suggestions, and sends them after the GIF (`Shim/ChatGIFTags.swift`) |
| Design system | | `compound-ios` (needed by the views), recoloured through its override API | our tokens: teal, coral, greys; teal for content outside #one, and inside the #one tab the #one red (#EB686E family) for everything, chat views included, with no teal but the bot marks (Thorsten, 2026-11-20). A bridged trait, `OneTintTrait`, set on the #one tab, turns every teal token red there (the colour rule in `App/Sources/Theme.swift`; it overrides the coral badges and mentions in `design/screens.html`) |
| Push | `NotificationClient` | | extension text, pusher registration, tap routing |
| Sign-in | OAuth 2.0, PKCE, dynamic registration | | one button, `ASWebAuthenticationSession` |

Left out while transplanting: encryption and verification UI, calls, location (it needs a map
provider), pinned messages, analytics and crash reporting. Voice messages and polls from other
clients still show; our app cannot record or create them. Element's name and logo never appear
(trademark). The full list with reasons: `Vendor/ElementX/UPSTREAM.md`.

**Kept apart so it can be re-synced or swapped.** Element X's code is Swift 6 with main-actor
default isolation, so it builds as its own framework, `ChatKit`; the app imports it.

```
Vendor/ElementX/            Element X files (Element's headers kept) and our code around them
  UPSTREAM.md               upstream tag, what is copied and left out, every local edit and why
  paths.txt, patches/       what scripts/sync-elementx.sh copies, and our edits to those files
  ElementX/, compound-ios/  the copy, same relative paths as upstream
  Shim/                     our code in ChatKit: ChatKitSession, room and thread screens, stand-ins
  Adapter/                  our code in the app target: implements ChatScreenProviding
App/Sources/Bridge/         the app's contract: ChatHost (app) and ChatScreenProviding (Vendor)
App/Sources/...             our shell: sign-in, room list, settings, navigation, push
```

- `scripts/sync-elementx.sh <tag>` copies the listed paths from an Element X release into
  `Vendor/ElementX/`, strips SwiftUI previews and mocks, and reapplies
  `Vendor/ElementX/patches/*.patch` (nine small, named edits today). A re-sync is a diff to
  review, not a hand merge. We re-sync when a fix we need lands upstream, not on every release.
  CI checks that the copy matches tag plus patches.
- Where upstream code names a part we left out, a same-named file in `Shim/` stands in, so the
  upstream file needs no patch.
- Our shell never reaches into Element X's code; it talks to ChatKit only through
  `App/Sources/Bridge/` and `Vendor/ElementX/Adapter/`. Swapping the views for exyte/Chat (MIT)
  later means replacing `Vendor/ElementX/`, not the shell.
- The SDK pin and the vendored Element X tag move separately. The bump workflow moves the SDK;
  a red build after an SDK bump may need a re-sync of the matching Element X release, which
  pins the same SDK line.

**Licence.** `LICENSE` is AGPL-3.0. `NOTICE` names Element Creations Ltd and New Vector Ltd
for the files under `Vendor/ElementX/` (their headers stay), and the Apache-2.0 matrix-rust-sdk.
Publishing AGPL code on the App Store under Alex's company is a question to settle before
launch, not before TestFlight.

**What the screens offer** (see the design proposal): channel list with unread markers,
channel timeline with thread summaries, a thread view, direct messages, mentions with
@-completion, images (send and view), reactions, a settings screen (name, picture, push,
sign out). Left out: calls, spaces, polls, location, voice messages, encryption UI.

## Following the SDK with near-zero upkeep

The bindings ship about twice a week and change their API often. The app follows them in
small steps, by machine, and a person only looks when something breaks.

1. **Pin.** `project.yml` names one exact SDK version. A build never changes by itself.
2. **Weekly bump.** `.github/workflows/sdk-bump.yml` checks every Monday. If a newer release
   exists it pushes the branch `sdk-bump` with the new pin and builds it. (The organisation
   does not let Actions open pull requests today; the branch build is the signal, and an
   agent opens the pull request.)
3. **Tests decide.** The build runs unit tests and a sign-in test against a throwaway Synapse
   on the runner: sign in, sync, the expected channels appear. Green: an agent merges. Red:
   the SDK changed an API we use; the compiler error names the line, usually a renamed
   parameter. Our SDK-touching code sits in `App/Sources/Matrix/`, so a break stays there.
4. **TestFlight.** A merge to `main` uploads a build (once the account exists); Thorsten,
   Alex and Philip get it on their phones.

Expected effort: most weeks nothing; a red bump an hour of agent time. Weekly steps keep each
API change small, which costs less than a monthly jump over eight releases.

## Build and CI

- `brand.env` is the one config spot: name, team, bundle id, server, sign-in pages, colours.
  `scripts/configure.sh` writes `App/Generated/Brand.swift` and generates the Xcode project
  with xcodegen; neither is committed.
- `scripts/build.sh build|test|integration` builds for the arm64 simulator (the SDK ships no
  x86_64 simulator slice), ad-hoc signed.
- **Lowest CPU priority on Thorsten's Mac** (Thorsten, 2026-11-21): `scripts/build.sh` and
  `scripts/perf.sh` start xcodebuild with `taskpolicy -b` and, every 20 s while it runs, lower
  the test simulator's process tree and the build services (`scripts/low-priority.sh`). The
  performance tests measure at normal priority and say so. GitHub's hosted runners keep normal
  priority; `IPHONEBLOG_PRIORITY=normal` turns it off anywhere.
- CI runs on GitHub's hosted `xcode-27` image (public preview; free for public repositories).
- One run per branch at a time. A new push to a pull request's branch cancels its older run;
  on `main` a new merge waits for the running build, and GitHub keeps only the newest waiting
  run, so `main` still builds its newest commit next. Cancelling on `main` too stopped every
  2.5-hour build when merges came hourly, and no build reached TestFlight for a day
  (2026-11-20/21).
- TestFlight: `fastlane/Fastfile`, switched on with the repository variable
  `TESTFLIGHT_ENABLED` once the App Store Connect key exists (README).

## Open points

- **CI time.** "Build and test" runs build, unit tests, the sign-in test and 74 UI tests in one
  job on GitHub's hosted `xcode-27` runner. Measured 2026-11-19: 87 minutes in the morning
  (UI step 69 minutes: 63 in the tests, slowest RichMessages 12, Threads 7, ThreadHeader 5,
  Contacts 5). In the evening the UI step took 66 minutes on one run and over 87 on two
  others, which hit the 120-minute job limit with no test failed. The limit is 180 minutes for now. Every new screen adds
  tests (hub, GIF picker, Markup), and five branches building at once share GitHub's macOS
  slots. Options, not yet decided:
  1. **Split the UI tests into three or four parallel jobs.** Build once (`build-for-testing`),
     hand the products to a matrix of `test-without-building -only-testing:` shards, each with
     its own test homeserver. About 30 to 35 minutes per run. Minutes stay free (public
     repository), but each run takes four macOS slots instead of one, so busy evenings queue.
     About a day's work.
  2. **On a pull request, run only the suites its files touch; the full set on `main`.** A map
     from paths to suites, plus the full set whenever `Vendor/`, `project.yml` or
     `TestServer.swift` change. 15 to 40 minutes per PR, free, half a day's work. A break the
     map misses shows up on `main` after the merge, where the build also gates TestFlight.
  3. **A self-hosted Mac.** A Mac mini runs the suite about twice as fast and nothing queues.
     About EUR 700 to 1,000 to buy, or roughly EUR 100 to 200 a month rented (price not
     checked), plus Xcode updates by hand. A public repository's pull requests would run
     strangers' code on it, so it needs runs from forks switched off or kept on GitHub's
     runners.

- Fonts: the blog uses Foro and Foro Sans, licensed for the web. Using them in the app needs
  an app licence from the foundry; until then the app uses the system font (SF Pro).
- Licence: AGPL-3.0, because of the transplanted Element X views (above). App Store question before launch.
