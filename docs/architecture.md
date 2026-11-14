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

**SwiftUI, iOS 17 and later.** One view tree for iPhone and iPad: `NavigationSplitView`
gives the iPad a channel column beside the conversation, and the iPhone a stack. The same
build runs on Apple-silicon Macs as an iPad app ("Designed for iPad"); no Mac-specific work.
iOS 17 covers every iPhone from the XS on.

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
`de.iphoneblog.matrix.ios.prod` and the gateway `https://matrix.iphoneblog.de/_matrix/push/v1/notify`.
A notification service extension (second target, shared app group) receives each push,
fetches the event with the SDK's notification client and writes "Name in #channel: text".
A tap opens the channel or the thread. Unencrypted rooms make this simple: no keys to share
with the extension. Apple's notification-filtering entitlement is requested for Alex's
account so the extension may drop pushes it cannot show.

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
- Licence: this repository is Apache-2.0, like the SDK. No AGPL code remains.
