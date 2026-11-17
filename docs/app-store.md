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

**When the app offers "Kontaktdaten teilen"** (the server's `POST /_iphoneblog/v1/contact-share`,
infra `docs/matrix.md`, "Sharing contact details"; no screen in the app yet), the same build adds
**Contact Info → Phone Number** to the labels (typed, mailed once through Mailjet, not stored by
us; declared because the mail service and the recipient keep it), and this paragraph to
`review_information/notes.txt` under "USER-GENERATED CONTENT":

> - "Kontaktdaten teilen": a #one member can send their own email address and/or a phone number they type, with a short note, to one other member. It goes as a single email from chat@iphoneblog.de to that member's address on file; nothing appears in the chat, there is no reply in the app, and the recipient's address is never shown. Limits: 5 an hour, 20 a day, 2 a day to the same person. Unwanted mails can be forwarded to ao@iphoneblog.de.

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

- **France**: Alex (the publisher, Account Holder), as supplier, files a "déclaration de fourniture" with ANSSI
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

## The External Link Account Entitlement (one link to #one on the website)

Thorsten (2026-11-17): go for it, as a news publication's reader app; it is how the app may point
to #one without In-App Purchase. Until Apple grants it the app shows no link and no buy prompt
(3.1.3(f)). Apple's terms, read 2026-11-17 on
[Distributing "reader" apps with a link to your website](https://developer.apple.com/support/reader-apps/):

- **Eligible:** apps whose primary functionality is magazines, newspapers, books, audio, music or
  video; people sign in to an account and reach content bought outside the app. Not eligible:
  apps with In-App Purchase on iOS, and real-time person-to-person services.
- **Who and how:** the **Account Holder** only (Alex), one request **per bundle id**, through the
  form `developer.apple.com/contact/request/external-link-account/` (behind sign-in; its questions
  are not readable without it).
- **The link:** shown once per screen, the same text wherever it appears; styled as a plain link
  (blue, underlined) that contains the domain; no price and no words about prices; opens a new
  window in the default browser, never a web view; goes to a site we own, with no query
  parameters, no redirect and no landing page in between. The URL goes in `Info.plist` and must
  match the binary App Review got; a new URL means a new submission.
- **The sheet:** before leaving the app, Apple's modal sheet. From iOS 16 it must be the system's,
  through StoreKit's External Link Account API; the app needs iOS 18.5, so always the system
  sheet. The app checks first that the person may make payments.
- **Keys:** entitlement `com.apple.developer.storekit.external-link.account` = true;
  `Info.plist` `SKExternalLinkAccount`, a dictionary of region code to URL with a `*` default
  (https, absolute, no query, at most 1,000 characters).
- **Review:** screenshots of the link and the sheet go into the review notes. No link to buy in
  the store texts: reader apps may link out only from inside the app.
- **Commission and reporting:** Apple's page states none. Secondary sources (2026) say the
  account link itself costs nothing in any storefront, because nothing is sold through it, and
  that the EU's commission applies to out-of-app *offers* under a different entitlement
  (StoreKit External Purchases or Offers, from 2026-10-01), which we do not use. **Unverified
  against Apple's own terms:** the terms Alex accepts in the request form are where this is
  settled; he reads the fee and reporting clauses before agreeing and sends them here.
- **United States:** since May 2025 US apps may link out without the entitlement. We still
  request it, because it covers every storefront.

**Our case for it:** iPhoneBlog.de is a news publication about Apple. The app opens on its
articles, readable without an account; every article has a discussion, which is its comment
section; #one is the publication's paid membership (weekly videos, a private video feed, the
members' area), sold on the website. There are no direct messages (Thorsten, 2026-11-16).
**The risk** is #one-Chat, a live members' room: Apple may count it as real-time
person-to-person. If Apple refuses, the app stays as it is (3.1.3(f), no link).

### Alex's steps (Account Holder)

1. Wait until `de.iphoneblog.app` exists in his team and the app record exists in App Store
   Connect (the bundle-id switch, iphoneblog-wordpress `docs/TODO.md`).
2. Sign in at developer.apple.com, open the reader-apps page above and follow its link to the
   **External Link Account Entitlement** request form.
3. Choose the app `de.iphoneblog.app`. Paste the answers below. Where the form asks something
   they do not cover, write it down and send it to Thorsten before answering.
4. Read the terms before agreeing: **the clauses on commission, reporting and storefronts.**
   Send Thorsten a copy or a screenshot of them.
5. Apple answers by mail. If granted, tell Thorsten: he adds the entitlement to the app id and
   the provisioning profile, and the app gets the link (below) in the next build, with
   screenshots of link and sheet in the review notes.

### The request text (English, to paste)

> **About the app.** iPhoneBlog is the app of iPhoneBlog.de, an independent German news
> publication about Apple, the iPhone and the App Store, published since [YEAR, Alex fills in].
> The app's primary functionality is the publication itself: every article, readable without an
> account, as on the website. Each article has a discussion section where readers comment on it.
>
> **Content type.** Newspapers and magazines: a news publication.
>
> **What is bought outside the app.** #one, the publication's paid membership: weekly videos, a
> private video feed and the members' community. Readers buy and manage #one
> only on our website, iphoneblog.de, paid through Stripe. Members sign in to the app with the
> same iphoneblog.de account to reach what they bought. The app offers no In-App Purchase and
> will not.
>
> **Accounts.** Readers sign in with their iphoneblog.de account. Accounts can be deleted inside
> the app.
>
> **The link.** One link, on the screen a signed-in reader without #one sees in the members'
> area: "Gehe zu iphoneblog.de, um #one abzuschließen oder zu verwalten." It opens
> https://www.iphoneblog.de/one/ in the default browser, after Apple's sheet. The page is ours,
> with no redirect.

### The link in the app, once granted (code only after the grant)

- **Where:** the #one tab's "Nur für #one-Mitglieder" screen (`OneMembersOnly` in
  `OneChatTab.swift`), under the sentence, above "Abmelden" and "Konto löschen". Nowhere else:
  not in Ich, not on the signed-out screen, not in the blog's web view.
- **Text:** "Gehe zu iphoneblog.de, um #one abzuschließen oder zu verwalten." in link style;
  no price, no "jetzt", no button look.
- **Action:** `ExternalLinkAccount.canOpen`, then `ExternalLinkAccount.open()` (Apple's sheet,
  then Safari). Hidden when `canOpen` is false.
- **Plist:** `SKExternalLinkAccount` = `{"*": "https://www.iphoneblog.de/one/"}`.
  `/one/` answered 200 with no redirect on 2026-11-17; keep it so (iphoneblog-wordpress smoke
  test checks `/one/`).
- **Tests:** a unit test that the link is shown only for a signed-in non-member when `canOpen`
  is true; a UI test that it is on that screen and nowhere else.
- **Review notes:** replace "the app does not mention or link to any purchase" with the
  paragraph on the link, and attach screenshots of link and sheet.

## Store listing

`fastlane/metadata/{de-DE,en-US}/`, `fastlane/metadata/primary_category.txt`. The listing
presents the app as the publication's app: articles first, the members' community second.
**No "Chat"** in name, subtitle, screenshots or the entitlement request (Thorsten, 2026-11-17);
the words are #one, Community, #one-connect. **The name is open** with Thorsten and Alex; the
files hold option 1.

| | Name | Subtitle de | Subtitle en | Verdict |
|---|---|---|---|---|
| 1 | iPhoneBlog (10) | News und #one-Community (23) | News and the #one community (27) | **Recommended.** The publication's own name, which readers search for; the subtitle carries the rest. Strongest for the reader-app case. |
| 2 | iPhoneBlog Connect (18) | Apple-News und #one-Community (29) | Apple news and #one community (29) | Possible. "Connect" reads as a social or messaging app, which the entitlement case argues against, and readers do not search for it. |
| 3 | iPhoneBlog #one (15) | Apple-News und Community (24) | Apple news and community (24) | Possible. Puts the paid membership in the name, though most of the app is free to read; non-members may think it is members only. |

All within Apple's 30 characters (counted with spaces). Category: **primary News, no secondary.**
Social Networking would invite the reviewer to judge the app as a social network first, and
the reader-app case rests on it being a publication.

**Screenshots** (6.9" iPhone, German, the demo account, no prices, no "Chat" in captions):

1. Blog: the article list. "Alle Artikel von iPhoneBlog.de"
2. One article, open. "Lesen ohne Anmeldung"
3. The discussion under that article. "Unter jedem Artikel: die Diskussion"
4. #one: the members' channel with a thread. "#one: die Community der Mitglieder"
5. @Mentions. "Antworten und Erwähnungen im Blick"
6. Ich: notifications, blocked users, report. "Melden, blockieren, selbst entscheiden"

**The tab label shows in shot 4:** the app calls the tab "#one-Chat". To keep "Chat" out of the
screenshots the tab becomes "#one" (or "#one-connect") in the app itself; the app session owns
that label.

## Review notes and demo account

`fastlane/metadata/review_information/notes.txt` (English). Before submitting, replace
`CONTACT_NAME` and `CONTACT_PHONE`; add a line on the word filter if it is on by then. The demo account (`demo_user.txt`, `demo_password.txt`, never in git: CI writes
them from the `apple` environment's secrets) must be a #one member **on live**: Apple reviews
against the App Store build, which signs in through live. That needs the chat on live (launch
step, Thorsten's yes).

## Upload

`fastlane ios beta` uploads to TestFlight only. The App Store needs a lane that runs `deliver`
with `fastlane/metadata`, the store screenshots (6.9" iPhone at least) and `submit_for_review`
off by default, on Alex's team, which publishes (2026-11-16), with his Admin API key in the
`apple` environment.
