# iphoneblog for iPhone (Matrix)

The iphoneblog chat app for iPhone. It is [Element X iOS](https://github.com/element-hq/element-x-ios)
with a small set of changes: the iphoneblog name, icon and colours, one fixed server
(`matrix.iphoneblog.de`), push through our own gateway, threads and QR sign-in on, calls
hidden, no analytics and no crash reports.

This repository holds only the changes. Each build takes Element X's newest release and
applies them, so a new upstream release needs no hand work.

This app is not made, endorsed or supported by Element. "Element" is a trademark of
Element Creations Ltd; the app carries none of its marks.

## How upstream updates flow

Every Monday the workflow in `.github/workflows/build.yml`:

1. finds the newest `release/x.y.z` tag of `element-hq/element-x-ios`,
2. runs `scripts/prepare.sh`, which clones that tag and applies the changes below,
3. builds the app for the simulator on GitHub's `xcode-27` macOS runner (public preview; `macos-26` has no Xcode 27),
4. uploads it to TestFlight, once that step is switched on (see "TestFlight").

A red scheduled build opens an issue labelled `build-failure`, or comments on the open one.
The last good TestFlight build stays installed on everyone's phone. A red build almost always
means upstream moved a line that `scripts/brand.py` expects or changed a hook's signature;
the error names the file.

Run it by hand: Actions, "Build", "Run workflow", optionally with a tag.

## What is changed

All changes sit in five places. Nothing edits upstream source by hand.

| Where | What it does |
|---|---|
| `brand.env` | The one config spot: display name, team id, bundle id, app group, server, push gateway, web pages, colours |
| `overlay/ElementX/Sources/Iphoneblog/IphoneblogHooks.swift` | Registers Element X's own hooks (`AppHooks.setUp`): fixed account provider, no other servers, push gateway, OAuth pages on the Matrix host, threads and "link new device" on for new installs, the blog's teal for buttons, links and accents, call buttons hidden in rooms, room details, member details and profiles |
| `overlay/ElementX/Resources/` | App icon, start-screen logo, start-screen and dialog backgrounds in the blog's colours. `scripts/make-assets.py` renders them from `brand/source/` |
| `scripts/brand.py` | Edits upstream files and stops when a line moved: app name, bundle id, team and app group in `app.yml`; associated domains (Element's out, `matrix.iphoneblog.de` in); `Secrets.swift` emptied, which switches off analytics (PostHog), crash reports (Sentry), bug reports (rageshake) and the map key; Element's name out of the notification sound names; the accent colour; it writes `IphoneblogBrand.swift` from `brand.env` |
| `patches/` | For changes no hook or script can make: `git apply --3way` applies each `*.patch` in name order. Empty today |

`scripts/check-marks.sh` runs inside `prepare.sh` and fails the build if Element's icon, logo,
name or domains survive.

## Build it yourself

You need Xcode 27 and `xcodegen` (`brew install xcodegen`).

```bash
scripts/prepare.sh                  # newest release into build/element-x-ios
scripts/prepare.sh release/26.11.0  # a given release
scripts/build-simulator.sh          # unsigned simulator build
```

The app lands in `build/DerivedData/Build/Products/Debug-iphonesimulator/ElementX.app`
(upstream's product name; the name on the home screen is `iphoneblog`).

## What the server must provide

The app expects these on `matrix.iphoneblog.de`:

- the Matrix client API, with the sign-in service (MAS) at `auth.matrix.iphoneblog.de`
  and QR login (`experimental_features: msc4108_enabled: true` in Synapse);
- Sygnal at `/_matrix/push/v1/notify`, with the app id `<BUNDLE_ID>.ios.prod`;
- `/.well-known/apple-app-site-association` listing `<TEAM_ID>.<BUNDLE_ID>` under
  `webcredentials` and `applinks`, so the OAuth redirect `https://matrix.iphoneblog.de/oauth/ios/<BUNDLE_ID>` returns to the app;
- `/apps/ios`, `/app/logo.png`, `/app/impressum`, `/app/terms`, `/app/privacy`, the OAuth client
  pages. Redirects to the blog's pages are fine; they must start on this host, because the
  sign-in service rejects client pages on another host.

## TestFlight

The upload step is written and switched off. To switch it on, once the Apple developer
account exists:

1. Put the account's team id into `TEAM_ID` in `brand.env`.
2. In App Store Connect create an API key with the Admin role (Admin, because automatic
   signing registers the app ids, app group and profiles), and the app record for `BUNDLE_ID`.
3. Add repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8_BASE64`
   (`base64 -i AuthKey_XXXX.p8`).
4. Create the APNs key for Sygnal (Certificates, Keys; Apple Push Notifications service).
5. Set the repository variable `TESTFLIGHT_ENABLED` to `true` and run the workflow.

## License

Element X iOS is licensed under the GNU Affero General Public License v3.0 (`LICENSE`).
This repository and every build made from it are under the same licence, and the source of
every build is this repository plus the upstream tag the build names.
