# iphoneblog chat for iPhone and iPad

The iphoneblog community chat: our own SwiftUI app on the Matrix engine
([matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk)), talking to
`chat.iphoneblog.de`. Members sign in with their iphoneblog.de account. Channels, threads,
direct messages, mentions, images and reactions; nothing else.

**State:** four tabs, as in the approved design previews (2026-11-15). **Blog** opens first and
needs no account: the blog itself in a web view, as WordPress's app view (`BLOG_WEB_URL`,
`?app=1`). The "Diskussion" link under an article (`iphoneblog-chat://diskussion?url=…`) opens
its discussion natively: the Matrix thread the article bot started. The app finds it by the
article's path in `links.json` and reads it from the bot's static files (`BLOG_API_URL`);
#one members write in it with the conversation views. **#one-Chat** is one channel,
`#one-chat:iphoneblog.de` (older alias `#allgemein`) in the space `#one:iphoneblog.de`;
membership is being joined to that space (the server accepts the bot's invites at once). Everyone else sees it locked, with the way to #one.
**@Mentions** (signed in only) lists the server's highlight notifications. **Ich** holds the
profile, the push switches (each one a server push rule) and the account. Sign-in through the
blog (MAS at `auth.iphoneblog.de`) is offered where writing starts. Push through our Sygnal
with a notification extension. The conversation views come from Element X under
`Vendor/ElementX/`, behind `App/Sources/Bridge/` (docs/architecture.md).

How it is built and why: [docs/architecture.md](docs/architecture.md).

## Decisions and open work

The chat project's decisions, the interfaces between its five pieces (server, WordPress, this
app, the website and the bot) and its open work live in one place, the WordPress repository:
`docs/chat.md`, ADR-0008 and `docs/TODO.md`, "Chat"
([docs/chat.md](https://github.com/iPhoneblog-web/iPhoneblog-Wordpress/blob/main/docs/chat.md)).
This README says how this repository is built; a decision about what the chat does goes there,
not here.

## Build it

You need Xcode 27, `xcodegen` and, for the sign-in test, `uv` (`brew install xcodegen uv`).

```bash
scripts/configure.sh               # brand.env → App/Generated/Brand.swift, iphoneblog.xcodeproj
scripts/build.sh build             # arm64 simulator build
scripts/build.sh test              # unit tests
scripts/test-homeserver.sh start   # throwaway Synapse on 127.0.0.1:8008 with a user and two rooms
set -a; . build/test-homeserver.env; set +a
scripts/build.sh integration       # sign in and list rooms against it
scripts/build.sh ui                # blog → Diskussion → swipe back; rich messages, composer, photo upload (UI_ONLY=Class[/test] for a part)
scripts/test-homeserver.sh stop
```

To see the app against the test server, launch it with `IPHONEBLOG_HOMESERVER`, and in a
debug build `IPHONEBLOG_DEV_USER` and `IPHONEBLOG_DEV_PASSWORD` to sign in by itself.

### Beta in the simulator

Beta sits behind the staff gate, whose second factor is a passkey the simulator does not have.
A Debug build in the simulator sends beta's machine token as the cookie `test_gate`, to
`beta.iphoneblog.de` only (infra `docs/staff-gate.md`, "A token for machines"). It reads the
token on the Mac from `~/.config/iphoneblog/test-gate-beta`; write that file once, from the
infra checkout's sops file (prints only the path):

```bash
mkdir -p ~/.config/iphoneblog && (umask 077; sops -d --extract '["test_gate_tokens"]["beta"]' ~/localprojects/infra/inventory/group_vars/all/secrets.sops.yml > ~/.config/iphoneblog/test-gate-beta) && echo "written: ~/.config/iphoneblog/test-gate-beta"
```

Release and TestFlight builds do not compile this path, and `scripts/check-release-clean.sh`
fails the TestFlight lane if one does.

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

The upload is written and switched off. The app ships as `de.iphoneblog.app` under Thorsten's
team W9N692KH39, to TestFlight and the App Store. The steps a person does at
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
