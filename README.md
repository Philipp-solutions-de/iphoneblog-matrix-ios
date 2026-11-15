# iphoneblog chat for iPhone and iPad

The iphoneblog community chat: our own SwiftUI app on the Matrix engine
([matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk)), talking to
`matrix.iphoneblog.de`. Members sign in with their iphoneblog.de account. Channels, threads,
direct messages, mentions, images and reactions; nothing else.

**State:** four tabs (decisions 2026-11-15). **Blog** opens first and needs no account: one
card per article thread (the bot's post), a tap opens the thread; members reply there. Signed
out it reads the Matrix host's read-only API (`BLOG_API_URL`), signed in the Blog room through
the SDK. **#one-Chat** holds the members' channels, threads and direct messages; non-members
see it locked with a link to the #one offer. **@Erwähnungen** and **Ich** as before. Sign-in
through the blog (MAS at `auth.iphoneblog.de`) is offered where writing starts. Push through
our Sygnal with a notification extension. The conversation views come from Element X under
`Vendor/ElementX/`, behind `App/Sources/Bridge/` (docs/architecture.md).

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

The upload is written and switched off. Until Alex's company account exists the app ships as
`de.iphoneblog.matrix.preview` under Thorsten's personal team. The steps a person does at
Apple, in order, with the commands that put the key into the repository:
[docs/apple-setup.md](docs/apple-setup.md).

## Signing certificate

Both chat apps (this one and `iphoneblog-zulip-ios`) sign with one Apple Distribution
certificate of Thorsten's team W9N692KH39: `Apple Distribution: Thorsten Philipp (W9N692KH39)`,
serial `123B7106234E1B22943005A94C3A9B37`, **valid until 2027-11-14**. Its `.p12` and passphrase
are the secrets `DIST_CERT_P12_BASE64` and `DIST_CERT_PASSWORD` in the environment `apple` of
both repositories. Builds import it into a throwaway keychain; App Store profiles come from the
API (`fastlane/Fastfile`, lane `archive`).

Renewal, in October 2027 (one year, Apple's limit):

1. On a Mac: `openssl genrsa -out dist.key 2048` and
   `openssl req -new -key dist.key -subj "/CN=iphoneblog CI Distribution/C=DE" -out dist.csr`.
2. `gh workflow run certificate.yml --repo Philipp-solutions-de/iphoneblog-matrix-ios --ref main -f csr="$(cat dist.csr)"`;
   the run prints the new certificate (public) between `CERTIFICATE_BASE64_BEGIN` and `_END`.
3. Decode it to `dist.cer`, build `dist.p12` with
   `openssl pkcs12 -export -legacy -inkey dist.key -in <(openssl x509 -inform DER -in dist.cer) -passout file:pass -out dist.p12`
   (`pass` from `openssl rand -hex 24`), and set both secrets in both repositories' `apple`
   environment from the files (`base64 -i dist.p12 | gh secret set DIST_CERT_P12_BASE64 --env apple --repo …`,
   `gh secret set DIST_CERT_PASSWORD --env apple --repo … < pass`).
4. Run the Signing check, then revoke the old certificate in developer.apple.com.

## License

GNU Affero General Public License v3.0 (`LICENSE`). The app takes its timeline, thread and
composer views from Element X iOS (AGPL-3.0), kept under `Vendor/ElementX/`; `NOTICE` names
the copyright holders. The skeleton holds no Element X code yet.
