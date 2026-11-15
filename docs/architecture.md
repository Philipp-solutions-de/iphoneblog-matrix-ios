# Architecture

The iphoneblog chat app is our own SwiftUI app on the Matrix engine (matrix-rust-sdk).
It does what a community needs: channels, threads, direct messages, mentions, images and
reactions. It has no calls, no spaces and no encryption screens. One codebase serves iPhone,
iPad and Apple-silicon Macs.

## The pieces

```
 iPhone / iPad / Mac                                   alex (behind edge)
 ┌───────────────────────────────┐                     ┌───────────────────────────┐
 │ SwiftUI screens               │                     │ matrix.iphoneblog.de      │
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

**Preset server, no discovery.** The client talks to `https://matrix.iphoneblog.de`
directly; people are `@name:iphoneblog.de`. No `.well-known/matrix` on the blog is needed.
Members never see a server field.

**Sign-in through the blog.** The app registers itself with the Matrix Authentication
Service at `auth.iphoneblog.de` (dynamic client registration), opens the sign-in page in
`ASWebAuthenticationSession`, and MAS sends the member on to WordPress. The callback uses the
custom scheme `de.iphoneblog.matrix:/oauth/callback`; MAS accepts a custom scheme when it is
the reverse of the client URI's host (`matrix.iphoneblog.de`), so no apple-app-site-association
file is needed for sign-in. The web sheet shares Safari's cookies: someone signed in to the
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
`<BUNDLE_ID>.ios.prod` (today `de.iphoneblog.matrix.preview.ios.prod`, Thorsten's team; see apple-setup.md) and the gateway `https://matrix.iphoneblog.de/_matrix/push/v1/notify`.
A notification service extension (second target, shared app group) receives each push,
fetches the event with the SDK's notification client and writes "Name in #channel: text".
A tap opens the channel or the thread. Unencrypted rooms make this simple: no keys to share
with the extension. Apple's notification-filtering entitlement is requested for Alex's
account so the extension may drop pushes it cannot show.

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
| Threads | thread focus, `ThreadListService`, thread subscriptions | `Screens/ThreadTimelineScreen`, `Screens/RoomThreadListScreen` | the Threads tab across rooms |
| Composer | send queue, replies, edits, `Mentions`, media upload | the composer toolbar and mention suggestions from `Screens/RoomScreen`, `Other/Pills` | plain-text mode only (no rich-text editor) |
| Media | thumbnails, files, upload with progress | `Screens/FilePreviewScreen`, `Screens/MediaPickerScreen` | |
| Design system | | `compound-ios` (needed by the views), recoloured through its override API | our tokens: teal, coral, greys |
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

## The Blog tab

**The blog's own pages, not a native feed** (Thorsten, 2026-11-15). The tab is a `WKWebView` of
`BlogWeb.defaultHome` (`App/Sources/Blog/BlogLinks.swift`; beta now, `https://www.iphoneblog.de/?app=1`
at launch). With `app=1` WordPress drops its header, menu, footer and sidebar, keeps the flag on
its own links, and writes under each article
`iphoneblog-chat://diskussion?url=<permalink>` (iphoneblog-wordpress PR #274). The rules for
every navigation are one pure function, `BlogNavigation.decide`, so they are unit-tested:

- `iphoneblog-chat://diskussion` opens the Diskussion view; nothing loads.
- A blog host (`iphoneblog.de`, `www`, the start page's host) without `app=1` loads again with it.
- `auth.phso.de` stays inside: beta's staff gate signs in there (but a passkey cannot work in a
  web view, so beta is reachable only where the gate already let the device in).
- Every other site, mail and phone link opens in Safari; embeds inside a page load as they are.

The web view lives as long as the app (one `BlogWebModel` in `BlogTab`), pulls to refresh, and
follows light and dark through the page's own `prefers-color-scheme`; the app paints the same
background under it so nothing flashes white.

**Diskussion finds its thread by the article's path.** The permalink carries the host that served
it (beta or www); `links.json` on the Matrix host is keyed by the www address. Both become
`ArticlePath.key` (decoded path, lower case, one trailing slash) before they are compared. The
file is read at most once a minute and again on a miss. No key means no thread yet, and the view
says so. Title and reply count come from the public thread file (`threads/<root>.json`) for
everyone. A signed-in #one member then gets the conversation views' thread screen with its
composer (`ChatScreens.provider.threadScreen`); anyone else gets the replies from the thread file,
read-only, with "Anmelden" (signed out) and "#one werden" where a composer would be. A push or a
link into the Blog room still lands here: `Router.blogPath` holds either a thread root (`$…`) or
`article:<permalink>` (`BlogRoute`).

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
