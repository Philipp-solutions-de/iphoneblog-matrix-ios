# iphoneblog chat for iPhone and iPad

The iphoneblog community chat: our own SwiftUI app on the Matrix engine
([matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk)), talking to
`matrix.iphoneblog.de`. Members sign in with their iphoneblog.de account. Channels, threads,
direct messages, mentions, images and reactions; nothing else.

**State: skeleton.** It signs in (blog sign-in, or username and password on a test server)
and lists the channels. Timelines, threads and push come after the design is agreed.

How it is built and why: [docs/architecture.md](docs/architecture.md).

## Build it

You need Xcode 27, `xcodegen` and, for the sign-in test, `uv` (`brew install xcodegen uv`).

```bash
scripts/configure.sh               # brand.env → App/Generated/Brand.swift, iphoneblog.xcodeproj
scripts/build.sh build             # arm64 simulator build
scripts/build.sh test              # unit tests
scripts/test-homeserver.sh start   # throwaway Synapse on 127.0.0.1:8008 with a user and two rooms
set -a; . build/test-homeserver.env; set +a
scripts/build.sh integration       # sign in and list rooms against it
scripts/test-homeserver.sh stop
```

To see the app against the test server, launch it with `IPHONEBLOG_HOMESERVER`, and in a
debug build `IPHONEBLOG_DEV_USER` and `IPHONEBLOG_DEV_PASSWORD` to sign in by itself.

## Where things are

| | |
|---|---|
| `brand.env` | The one config spot: name, team id, bundle id, server, sign-in pages, colours |
| `project.yml` | The Xcode project for xcodegen, with the pinned SDK version |
| `App/Sources/Matrix/` | Everything that touches the SDK: client, session, sync, room list |
| `App/Sources/Screens/` | SwiftUI screens |
| `App/Resources/Assets.xcassets` | Icon, logo, colours; `scripts/make-assets.py` renders them from `brand/source/` |
| `Tests/` | Unit tests, and the sign-in test against a real Synapse |
| `.github/workflows/build.yml` | Build and tests on every push and weekly; TestFlight when switched on |
| `.github/workflows/sdk-bump.yml` | Weekly: move the SDK pin to the newest release on branch `sdk-bump` and build it |

## TestFlight

The upload is written and switched off. Once Alex's company developer account exists:

1. Put its team id into `TEAM_ID` in `brand.env`.
2. In App Store Connect create the app record for `BUNDLE_ID` and an API key with the Admin
   role (automatic signing registers the app id, app group and profiles with it).
3. Add the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8_BASE64`
   (`base64 -i AuthKey_XXXX.p8`).
4. Create the APNs key for Sygnal (app id `de.iphoneblog.matrix.ios.prod`).
5. Set the repository variable `TESTFLIGHT_ENABLED` to `true`.

## License

Apache License 2.0 (`LICENSE`), like the Matrix SDK it builds on.
