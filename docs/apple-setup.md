# Apple setup: what Thorsten clicks

Until Alex's company account exists, the app ships to TestFlight under Thorsten's personal
developer team as **iphoneblog Chat Preview**, bundle id `de.iphoneblog.matrix.preview`.
This page is every step a person has to do at Apple, in order. Everything else (identifiers,
capabilities, certificates, profiles, builds, uploads) runs in GitHub Actions with an App Store
Connect API key.

Checked against Apple's and fastlane's documentation on 2026-11-14. Links at each step.
**Unverified** marks what the documentation does not settle.

No key or secret ever goes into a chat, an issue or a log. The commands below read the
values from a file or from a hidden prompt.

Repository: `Philipp-solutions-de/iphoneblog-matrix-ios`. Run the `gh` commands on your Mac.

## 1. Note your Team ID (2 minutes)

developer.apple.com/account > Membership details > **Team ID** (10 characters). It is not
secret; it is printed in every app.

```bash
gh variable set APPLE_TEAM_ID --repo Philipp-solutions-de/iphoneblog-matrix-ios --body XXXXXXXXXX
```

## 2. Ask for API access (once, then wait for Apple)

App Store Connect > **Users and Access** > **Integrations** > App Store Connect API >
**Request Access**, tick the terms, **Submit**. Only the Account Holder can do this; Apple
approves "case by case". [Source](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

**Unverified:** whether Apple grants API access to individual (non-company) accounts. The page
names no restriction.

## 3. Create the API key (after approval)

App Store Connect > **Users and Access** > **Integrations** > **Team Keys** > **+** >
name `github-iphoneblog-matrix` > Access **Admin** > **Generate**. Then **Download** the
`.p8` file. Apple lets you download it **once**. Note the **Key ID** (in the row) and the
**Issuer ID** (above the table). [Source](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

Why Admin: signing on GitHub's machines uses Apple's cloud-managed distribution certificate.
Apple documents no role for API keys there; developer-forum reports say Developer and App
Manager keys fail with "Cloud signing permission error" and only Admin keys work
([forum](https://developer.apple.com/forums/thread/698117); not official documentation).
A team key, not an individual key, is needed for the provisioning endpoints
([fastlane](https://docs.fastlane.tools/app-store-connect-api/)).

Put it into the repository (the two IDs at a hidden prompt, the key from its file):

```bash
gh secret set ASC_KEY_ID --repo Philipp-solutions-de/iphoneblog-matrix-ios
```

```bash
gh secret set ASC_ISSUER_ID --repo Philipp-solutions-de/iphoneblog-matrix-ios
```

```bash
base64 -i ~/Downloads/AuthKey_KEYID.p8 | gh secret set ASC_KEY_P8_BASE64 --repo Philipp-solutions-de/iphoneblog-matrix-ios
```

Then move the `.p8` into your password manager and delete it from Downloads.

## 4. Register the App Group (by hand: the API cannot)

developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Identifiers** >
**+** > **App Groups** > Continue > Description `iphoneblog Chat Preview`, Identifier
`group.de.iphoneblog.matrix.preview` > Continue > **Register**.
[Source](https://developer.apple.com/help/account/identifiers/register-an-app-group).
The App Store Connect API has no resource for app groups.

## 5. Register the app ids (GitHub does it)

```bash
gh workflow run apple-setup.yml --repo Philipp-solutions-de/iphoneblog-matrix-ios
```

The workflow registers `de.iphoneblog.matrix.preview` (Push Notifications, App Groups) and
`de.iphoneblog.matrix.preview.nse` (App Groups) through the API
([bundle ids](https://developer.apple.com/documentation/appstoreconnectapi/bundle-ids),
[capabilities](https://developer.apple.com/documentation/appstoreconnectapi/bundle-id-capabilities)).
Running it again changes nothing.

Then tie the group to both ids, because the API only switches the capability on:
**Identifiers** > `de.iphoneblog.matrix.preview` > App Groups **Configure** > tick
`group.de.iphoneblog.matrix.preview` > Continue > **Save**. The same for
`de.iphoneblog.matrix.preview.nse`. **Unverified:** whether Xcode's automatic signing on the
build machine does this by itself; doing it by hand costs a minute and removes the doubt.

## 6. Create the app record (by hand: the API cannot)

App Store Connect > **Apps** > **+** (top left) > **New App**:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `iphoneblog Chat Preview` (2 to 30 characters; the name under the icon stays `iphoneblog`) |
| Primary Language | German |
| Bundle ID | `de.iphoneblog.matrix.preview` (in the list after step 5) |
| SKU | `iphoneblog-matrix-preview` |
| User Access | Full Access |

[Source](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app).
There is no API for this (`POST /v1/apps` does not exist), and fastlane's `produce` needs an
Apple ID login, which we do not use. Bundle ID and SKU cannot be changed later. If Apple says
the name is taken, use `iphoneblog Matrix Preview` and tell the agent, which updates
`APP_STORE_NAME` in `brand.env`.

## 7. Create the push key for Sygnal

developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Keys** > **+** >
name `sygnal-iphoneblog` > tick **Apple Push Notification service (APNs)** > **Configure** >
Environment **Production**, Key Restriction **Team Scoped** > Save > Continue > Register >
**Download** (once). Note the **Key ID**.
[Source](https://developer.apple.com/help/account/keys/create-a-private-key).

Production, because TestFlight builds talk to Apple's production push service. Sygnal needs the
Key ID, your Team ID, the `.p8` and the topic `de.iphoneblog.matrix.preview`
([source](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)).

Put the key into infra's secrets, from the infra checkout, without the value passing through a
chat:

```bash
jq -Rs . < ~/Downloads/AuthKey_PUSHKEYID.p8 | sops set --value-stdin inventory/group_vars/all/secrets.sops.yml '["sygnal_apns_key_p8"]'
```

```bash
sops set inventory/group_vars/all/secrets.sops.yml '["sygnal_apns_key_id"]' '"PUSHKEYID"'
```

The two secret names are agreed with the Matrix server session in
`2026-11-14_interfaces.md`. Then move the `.p8` into your password manager.

## 8. Invite Alex and Philip

App Store Connect > **Users and Access** > **People** > **+** > first name, last name, email >
role **Customer Support**, app access limited to `iphoneblog Chat Preview` > **Invite**. Each
accepts the email invitation. [Source](https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users).
People you invite into an individual account get App Store Connect only, not your developer team.

**Unverified:** whether Customer Support is enough to be an internal tester. Apple says
internal testers are "App Store Connect users with access to your content". If TestFlight
does not offer them in step 9, change their role to **Marketing**.

## 9. Switch TestFlight on and make the tester group

```bash
gh variable set TESTFLIGHT_ENABLED --repo Philipp-solutions-de/iphoneblog-matrix-ios --body true
```

```bash
gh workflow run build.yml --repo Philipp-solutions-de/iphoneblog-matrix-ios
```

When the first build shows up (Apps > iphoneblog Chat Preview > **TestFlight**, after about
15 minutes of processing): **+** next to Internal Testing > name `Verifiers` > tick **Enable
automatic distribution** > Create > **Invite Testers** > tick yourself, Alex, Philip > **Add**.
[Source](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
Up to 100 internal testers. Each installs **TestFlight** from the App Store and accepts the
invitation. Builds expire after 90 days; every merge makes a new one.

Export compliance is answered in the app (`ITSAppUsesNonExemptEncryption = NO`), so builds do
not stop at "Missing Compliance"
([source](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds)).
**Unverified:** that internal builds skip Beta App Review; Apple ties review to external
testers only.

## Not needed now

- **Notification filtering entitlement** (`com.apple.developer.usernotifications.filtering`).
  It lets the push extension drop a push without showing it. Our extension always shows the
  message, so it does not need it. Request it with Alex's company account if we ever do
  ([form](https://developer.apple.com/contact/request/notification-service)).
- **Distribution certificates and profiles**: Xcode creates them on the build machine with
  the Admin key (cloud-managed certificate).

## When Alex's company account exists

Repeat steps 1 to 9 in his account with `BUNDLE_ID="de.iphoneblog.matrix"`,
`APP_GROUP_ID="group.de.iphoneblog.matrix"`, a new store name and SKU in `brand.env`, his
Team ID in `APPLE_TEAM_ID`, his key in the three secrets, and his push key for Sygnal (app id
`de.iphoneblog.matrix.ios.prod`). Testers move to the new app; the preview app is then
removed from TestFlight.
