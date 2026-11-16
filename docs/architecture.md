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

**Four tabs, the blog as the front page.** Blog, #one-Chat, @Mentions (signed in only), Ich,
as in the approved previews; every visual value lives in `App/Sources/Theme.swift`, light and
dark by the system. The Blog tab is a `WKWebView` on WordPress's app view (`?app=1`, which
drops banner, header, menu and footer), not native article cards: the blog renders articles,
paywall included, exactly as the site does, and the app adds only the discussion. The web
view routes taps only: a "Diskussion" link opens the native discussion, a link to the blog
keeps `app=1`, any other site opens in Safari. Redirects and the page's own loads go where the
server sends them, so beta's staff gate (Authelia at `auth.phso.de`) signs in inside the view.
One web view lives as long as the app (`BlogWebModel`): a tab switch, a sign-in or a
discussion never reloads the page the reader is on. The discussion uses the system back
button, so a swipe from the left edge returns to the blog where the reader was; a custom back
button would switch that swipe off (Thorsten's test of build 70).

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

**Threads work as in Slack.** Under a message with replies, a row shows up to three repliers,
"n Antworten" in teal and when the last reply came; unread replies make it bold with a dot. A
tap on a message opens its thread, also to start one (links, mentions and pictures keep their
own tap), and the long-press menu offers "Im Thread antworten" first. "Threads" at the top of
#one-Chat lists the threads you started or wrote in, newest first, with a count of those with
news; it sits there, beside the channel as in Slack, so @Mentions stays the list of people who
named you. Counts come from the server's thread relations (`ChatThreadActivity`): the SDK's
timeline summary and thread list counted 3 and 9 for a thread with 6 replies. Unread is per
device (`ChatThreadSeen`). Not built: "Auch an #one-Chat senden" (Matrix has no event that is
both a thread reply and a channel message; it would take two events), push for replies in
threads you are in without a mention (Synapse sends none), and thread rows in the Blog tab,
which shows the website.

**No direct messages.** The app offers no way to start one (a tap on a person opens nothing),
and direct rooms stay out of #one-Chat, Threads and @Mentions; the server refuses to create
them (Thorsten, 2026-11-16).

**Search is Matrix's own.** The magnifier in #one-Chat sends `POST /_matrix/client/v3/search`
(room_events, filtered to the channel, newest first, `next_batch` paging); the rooms are
unencrypted, so Synapse can read them, and there is no index of our own. A hit shows sender,
time and the words marked; a thread reply opens its thread, a channel message scrolls the
channel to it (`ChatKitSession.focus`, Element X's focus on an event). Synapse stems in English
only, hard-coded in its source, so German inflections may not match; the empty state suggests
the word stem. @Mentions filters its loaded list on the device.

**Tab badges come from the server's counts.** The SDK counts a room's unread mentions in the
last few events it holds, so a mention with six or more messages after it dropped out. A room's
mention count is the larger of the SDK's and the server's notification list (the one @Mentions
reads); `ChatSession` puts the #one-Chat and @Mentions badges on `Router`, which `MainView`
observes (before, the @Mentions badge never appeared). iOS 26's tab bar does not expose badges
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

**@Mentions from the server.** The tab lists `GET /notifications?only=highlight`: the server
already decides what mentions me and keeps the read state across devices. The push switches
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
| Timeline | `Timeline`: pagination, local echo, send queue, edits, reactions, receipts | `Screens/Timeline` (cells, list, reactions, replies, thread summaries), `Services/Timeline` (SDK wrapper, view items) | adapters, our colours and type, cells we do not want removed |
| Threads | thread focus, `ThreadListService`, thread subscriptions | `Screens/ThreadTimelineScreen`, `Screens/RoomThreadListScreen` | the article discussions and the threads in #one-Chat |
| Composer | send queue, replies, edits, `Mentions`, markdown to HTML, media upload | the composer, its formatting toolbar (+ › Textformatierung) and mention suggestions from `Screens/RoomScreen`, `Other/Pills` | no polls, no voice messages |
| Media | thumbnails, files, upload with progress | `Screens/FilePreviewScreen`, `Screens/MediaPickerScreen`, `Screens/MediaUploadPreviewScreen`; link previews through Apple's `LPMetadataProvider` (the phone fetches the page, not Synapse's preview_url) | the upload progress bar under a sending photo, video or file (`Shim/ChatUploadProgress.swift`); animated GIFs play from the original and go out unchanged (Element X), with Reduce Motion as their first frame (patch) |
| Design system | | `compound-ios` (needed by the views), recoloured through its override API | our tokens: teal, coral, greys; teal for all content, coral only for #one and sign-in (the colour rule in `App/Sources/Theme.swift`; it overrides the coral badges and mentions in `design/screens.html`) |
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
- CI runs on GitHub's hosted `xcode-27` image (public preview; free for public repositories).
- TestFlight: `fastlane/Fastfile`, switched on with the repository variable
  `TESTFLIGHT_ENABLED` once the App Store Connect key exists (README).

## Open points

- Fonts: the blog uses Foro and Foro Sans, licensed for the web. Using them in the app needs
  an app licence from the foundry; until then the app uses the system font (SF Pro).
- Licence: AGPL-3.0, because of the transplanted Element X views (above). App Store question before launch.
