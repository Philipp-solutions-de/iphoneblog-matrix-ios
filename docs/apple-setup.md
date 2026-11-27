# Apple setup for both chat apps: what Thorsten clicks

Until Alex's company account exists, both iphoneblog chat apps ship to TestFlight under
Thorsten's personal developer team. This page is every step a person has to do at Apple, for
**both apps at once**, in order. Everything else (identifiers, capabilities, certificates,
profiles, builds, uploads) runs in GitHub Actions with one App Store Connect API key.

| | Matrix app | Zulip app |
|---|---|---|
| Repository | `Philipp-solutions-de/iphoneblog-matrix-ios` | `Philipp-solutions-de/iphoneblog-zulip-ios` |
| Bundle id | `de.iphoneblog.matrix.preview` | `de.iphoneblog.zulip.preview` |
| Extension | `de.iphoneblog.matrix.preview.nse` | `de.iphoneblog.zulip.preview.NotificationService` |
| Share extension | `de.iphoneblog.matrix.preview.share` | none |
| App group | `group.de.iphoneblog.matrix.preview` | `group.de.iphoneblog.zulip.preview` |
| App record name | `iphoneblog Chat Preview` | `iphoneblog Z Preview` |
| SKU | `iphoneblog-matrix-preview` | `iphoneblog-zulip-preview` |
| Identifier workflow | `apple-setup.yml` | `apple-setup.yml` |

Checked against Apple's and fastlane's documentation on 2026-11-14; links at each step.
**Unverified** marks what the documentation does not settle. No key or secret ever goes into
a chat, an issue or a log: the commands read values from a file or a hidden prompt. Run the
`gh` and `sops` commands on your Mac.

## What the key can do, and how it is fenced

The API key is an Admin key of your App Store Connect account: with it, anyone holding it
can upload builds, change app records and testers, create certificates and profiles, and
manage users in your account, but not touch your Apple ID, payments or agreements. It lives
only in a GitHub environment called `apple` in each of the two repositories, which only jobs
on `main` can open (no pull requests, forks or other branches; actions, fastlane and XcodeGen
pinned to exact versions), and you can revoke it at any time under Users and Access >
Integrations.

## 1. Accept the current agreement

App Store Connect > **Business**. If a new Program License Agreement waits there, accept it.
Apple creates no app record before that.

## 2. Team ID into both repositories

developer.apple.com/account > Membership details > **Team ID** (10 characters; not secret).

```bash
for r in Philipp-solutions-de/iphoneblog-matrix-ios Philipp-solutions-de/iphoneblog-zulip-ios; do
  gh variable set APPLE_TEAM_ID --repo "$r" --body XXXXXXXXXX
done
```

## 3. Ask for API access (once, then wait for Apple)

App Store Connect > **Users and Access** > **Integrations** > App Store Connect API >
**Request Access**, tick the terms, **Submit**. Only the Account Holder can do this; Apple
approves "case by case". [Source](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

**Unverified:** whether Apple grants API access to individual accounts; the page names no
restriction.

## 4. One API key, into both repositories

App Store Connect > **Users and Access** > **Integrations** > **Team Keys** > **+** > name
`github-iphoneblog-apps` > Access **Admin** > **Generate**. **Download** the `.p8` (Apple
offers it **once**). Note the **Key ID** (in the row) and the **Issuer ID** (above the table).
[Source](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

Why Admin: signing on GitHub's machines uses Apple's cloud-managed distribution certificate.
Apple documents no role for API keys there; developer-forum reports say Developer and App
Manager keys fail with "Cloud signing permission error" and only Admin keys work
([forum](https://developer.apple.com/forums/thread/698117); not official documentation). A
team key, not an individual key, is needed for the provisioning endpoints
([fastlane](https://docs.fastlane.tools/app-store-connect-api/)).

The secrets go into the environment `apple` of each repository, not into repository or
organisation secrets (organisation secrets cannot be tied to an environment). `gh` asks for
the Key ID and Issuer ID at a hidden prompt:

```bash
P8=~/Downloads/AuthKey_KEYID.p8
for r in Philipp-solutions-de/iphoneblog-matrix-ios Philipp-solutions-de/iphoneblog-zulip-ios; do
  gh secret set ASC_KEY_ID --env apple --repo "$r"
  gh secret set ASC_ISSUER_ID --env apple --repo "$r"
  base64 -i "$P8" | gh secret set ASC_KEY_P8_BASE64 --env apple --repo "$r"
done
```

Then move the `.p8` into your password manager and delete it from Downloads.

## 5. Register the two app groups (by hand: the API cannot)

developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Identifiers** > **+**
> **App Groups** > Continue > description and identifier > Continue > **Register**. Twice:
`group.de.iphoneblog.matrix.preview` and `group.de.iphoneblog.zulip.preview`.
[Source](https://developer.apple.com/help/account/identifiers/register-an-app-group). The App
Store Connect API has no resource for app groups.

## 6. Register the app ids (GitHub does it), then tie the groups

```bash
gh workflow run apple-setup.yml --repo Philipp-solutions-de/iphoneblog-matrix-ios
```

```bash
gh workflow run apple-setup.yml --repo Philipp-solutions-de/iphoneblog-zulip-ios
```

Each registers its app and extension ids and turns on Push Notifications (app), App Groups
(both) and, in the Matrix app, Associated Domains (app: passkeys at `auth.phso.de` in the Blog
tab's web view, and chat links on `chat.iphoneblog.de` as universal links, whose
apple-app-site-association the chat server serves) through the API (the passkeys also need
`https://auth.phso.de/.well-known/apple-app-site-association` to name `<team>.<bundle id>`:
when the bundle id or team changes for the release, change `well_known` for auth.phso.de in
the infra repository's `inventory/host_vars/moon.yml` and run `playbooks/door.yml --limit moon`) ([bundle ids](https://developer.apple.com/documentation/appstoreconnectapi/bundle-ids),
[capabilities](https://developer.apple.com/documentation/appstoreconnectapi/bundle-id-capabilities)).
Running them again changes nothing. Check both went green on the repositories' Actions pages.

The API only switches the App Groups capability on; it does not pick the group. For each of
the five ids in the table (app, extensions): **Identifiers** > the id > App Groups **Configure** > tick its app's
group > Continue > **Save**. **Unverified:** whether automatic signing on the build machine
does this by itself; by hand it takes a minute and removes the doubt.

## 7. Two app records (by hand: the API cannot)

App Store Connect > **Apps** > **+** (top left) > **New App**, once per app with the values
from the table: Platforms **iOS**, Name, Primary Language **German**, Bundle ID (in the list
after step 6), SKU, User Access **Full Access** > **Create**.
[Source](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app).

There is no API for this (`POST /v1/apps` does not exist), and fastlane's `produce` needs an
Apple ID login, which we do not use. Names are 2 to 30 characters; bundle ID and SKU cannot
change later. If a name is taken, use `iphoneblog Matrix Preview` or `iphoneblog Zulip Preview`
and tell the agent, which updates the repository's config.

## 8. One push key for both servers

developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Keys** > **+** > name
`iphoneblog push` > tick **Apple Push Notification service (APNs)** > **Configure** >
environment **Production** (TestFlight builds use production), key restriction **Team
Scoped** (one key serves every app of the team) > Save > Continue > Register > **Download**
(once). Note the **Key ID**. [Source](https://developer.apple.com/help/account/keys/create-a-private-key);
Apple: "You can use one APNs signing key to authenticate tokens for multiple apps"
([source](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)).

The key goes to the servers, not to GitHub. From an infra worktree, the same file under the
Zulip server's and Sygnal's names (replace the file name, Key ID and Team ID):

```bash
SOPS=inventory/group_vars/all/secrets.sops.yml
P8=~/Downloads/AuthKey_PUSHKEYID.p8
for k in zulip_apns_key sygnal_apns_key_p8; do jq -Rs . < "$P8" | sops set --value-stdin "$SOPS" "[\"$k\"]"; done
for k in zulip_apns_key_id sygnal_apns_key_id; do sops set "$SOPS" "[\"$k\"]" '"PUSHKEYID"'; done
for k in zulip_apns_team_id sygnal_apns_team_id; do sops set "$SOPS" "[\"$k\"]" '"XXXXXXXXXX"'; done
```

Then move the `.p8` into your password manager. The six names are agreed in
`2026-11-14_interfaces.md`.

## 9. Invite Alex and Philip (once, for both apps)

App Store Connect > **Users and Access** > **People** > **+** > name and Apple Account email >
role **Developer**, app access limited to the two apps > **Invite**. Each accepts the email.
[Source](https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users).
People invited into an individual account get App Store Connect only, not your developer team.
**Unverified:** whether a smaller role than Developer can be an internal tester; Apple says
internal testers are "App Store Connect users with access to your content".

## 10. Switch TestFlight on and make the tester groups

```bash
for r in Philipp-solutions-de/iphoneblog-matrix-ios Philipp-solutions-de/iphoneblog-zulip-ios; do
  gh variable set TESTFLIGHT_ENABLED --repo "$r" --body true
done
```

```bash
gh workflow run build.yml --repo Philipp-solutions-de/iphoneblog-matrix-ios --ref main
```

```bash
gh workflow run build.yml --repo Philipp-solutions-de/iphoneblog-zulip-ios --ref main
```

When a first build appears (each app > **TestFlight**, after some minutes of processing):
**+** next to Internal Testing > name `Verifiers` > tick **Enable automatic distribution** >
Create > **Invite Testers** > tick yourself, Alex, Philip > **Add**. Once per app.
[Source](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
Each tester installs Apple's **TestFlight** app and accepts both invitations. Builds expire
after 90 days; every merge to `main` makes a new one.

Both apps declare `ITSAppUsesNonExemptEncryption = NO`, so builds do not stop at "Missing
Compliance" ([source](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds)).
**Unverified:** that internal builds skip Beta App Review; Apple ties review to external testers.

## Not needed now

- **Notification filtering entitlement** (`com.apple.developer.usernotifications.filtering`):
  lets a push extension drop a push without showing it. Both extensions always show the
  message. Request it later if needed ([form](https://developer.apple.com/contact/request/notification-service)).
- **Certificates and profiles**: Xcode creates them on the build machine with the Admin key.

## When Alex's company account exists

Repeat steps 1 to 10 in his account with the final ids (`de.iphoneblog.matrix`,
`de.iphoneblog.zulip`), his Team ID, his API key in both `apple` environments and his push key
under the same six sops names. An app that was never released cannot move between accounts,
so testers install the new apps once and the preview apps leave TestFlight.
