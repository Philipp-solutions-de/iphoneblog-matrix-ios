# The App Store

What Apple needs before this app goes to the App Store, and where each answer lives. The open
work is in iphoneblog-wordpress `docs/TODO.md`, "App Store readiness"; this page is how things
are. Apple's texts quoted here were read on 2026-11-16.

## The app's own answers

| Apple asks | Answer | Where |
|---|---|---|
| In-app purchase (3.1.1) | None. #one is sold on the website; the app shows no price, buy button or link to buy (`SHOW_PURCHASE` off). A free app beside a paid web service, 3.1.3(f) | `brand.env`, review notes |
| User content (1.2) | Report a message or a person (mailed to the moderation contact ao@iphoneblog.de), block a person; no word filter (Thorsten, 2026-11-16: added only if review refuses for its lack) | `App/Sources/Moderation/`, server module (infra) |
| Account deletion (5.1.1(v)) | Ich → Konto löschen → the website's `/konto/loeschen/` | `AccountDeletionView.swift`, iphoneblog-wordpress |
| Privacy manifest | `PrivacyInfo.xcprivacy` in the app, the notification extension and ChatKit | below |
| Push permission | Asked on the first visit to #one-Chat, after one sentence; not at sign-in | `PushPrimer.swift` |
| Web view | Its main frame stays on iphoneblog.de; anything else opens in Safari | `BlogURLPolicy.swift` |
| Store texts, review notes | `fastlane/metadata/` (deliver's layout) | below |

## Privacy manifests

Three files, one per bundle that runs code: `App/Resources/PrivacyInfo.xcprivacy`,
`NotificationExtension/PrivacyInfo.xcprivacy` and `Vendor/ElementX/Shim/PrivacyInfo.xcprivacy`
(ChatKit). xcodegen adds each to its target's resources by itself.

- **Required reasons**: UserDefaults `CA92.1` (the app's own settings: emoji, read threads, the
  article rule) in the app and ChatKit; file timestamps `C617.1` (files in the app's container
  and app group: the SDK's store, log rotation in `Tracing.swift`) in all three. Nothing reads
  disk space, boot time or the keyboard list. Check again when a package is added or the SDK
  bumped: `grep -rE "UserDefaults|modificationDate|creationDate|systemUptime|volumeAvailableCapacity"`.
- **Tracking**: none, no tracking domains. Element X's PostHog and Sentry are cut
  (`Vendor/ElementX/Shim/Analytics.swift`).
- **Collected** (the app's file only), all linked to the person, for app functionality, none for
  tracking: name, email address, user ID, messages, photos or videos, audio (voice messages),
  other user content (reactions, reports).
- Of the 21 packages only Kingfisher and Mantis ship their own manifest.

## App Privacy labels (App Store Connect → App Privacy)

Enter the same as the manifest: **Data Linked to You**, purpose **App Functionality** only, for

| Category | Type | Why |
|---|---|---|
| Contact Info | Name, Email Address | the account, from iphoneblog.de's sign-in |
| Identifiers | User ID | `@name:iphoneblog.de` |
| User Content | Emails or Text Messages, Photos or Videos, Audio Data, Other User Content | messages, pictures, voice messages, reactions and reports |

**Data Used to Track You**: none. **Not collected**: purchases (Stripe on the website, not in the
app), location, contacts, browsing history, diagnostics, usage data. Privacy policy URL
`https://www.iphoneblog.de/datenschutz/`, once the chat's section is there.

## Age rating

App Store Connect's questionnaire: **user-generated content and messaging: yes**; **unrestricted
web access: no**, because `BlogURLPolicy` keeps the web view on iphoneblog.de; every content
question (violence, sexual content, gambling, contests, medical) **none**; no location sharing
(the SDK's live location is not offered in the composer). Expected rating 13+.

## Export compliance

The app uses HTTPS, which is exempt, and ships the Matrix SDK's own cryptography (vodozemac:
Curve25519, Ed25519, AES-256, HMAC-SHA-256, HKDF), standard algorithms not provided by iOS.
Thorsten's answer (2026-11-16): standard encryption, with the French declaration.

- **France**: the publisher, as supplier, files a "déclaration de fourniture" with ANSSI
  (online at demarche.numerique.gouv.fr) and uploads ANSSI's attestation in App Store Connect →
  App Information → App Encryption Documentation. Until it arrives, France stays unticked under
  Pricing and Availability.
- **App Store Connect**: "Standard encryption algorithms instead of, or in addition to, using
  or accessing the encryption within Apple's operating system"; available in France: yes, with
  the attestation. Apple then gives a key: set `ITSAppUsesNonExemptEncryption: true` and
  `ITSEncryptionExportComplianceCode` in `project.yml`, so builds no longer ask.
- **US**: nothing to file. A free mass-market app with standard encryption is 5D992.c, and since
  BIS's rule of March 2021 it needs no annual self-classification report. **Unverified** for
  this app until Apple's form has been answered.

## Review notes and demo account

`fastlane/metadata/review_information/notes.txt` (English). Before submitting, replace
`CONTACT_NAME` and `CONTACT_PHONE`; add a line on the word filter if it is on by then. The demo account (`demo_user.txt`, `demo_password.txt`, never in git: CI writes
them from the `apple` environment's secrets) must be a #one member **on live**: Apple reviews
against the App Store build, which signs in through live. That needs the chat on live (launch
step, Thorsten's yes).

## Upload

`fastlane ios beta` uploads to TestFlight only. The App Store needs a lane that runs `deliver`
with `fastlane/metadata`, the store screenshots (6.9" iPhone at least) and `submit_for_review`
off by default, from the publisher's account and bundle id (`de.iphoneblog.matrix`). It waits on
the publisher's account.
