# Vendor/ElementX: Element X's chat views

Element X iOS's timeline, thread, composer, media and pill code, built as the framework
`ChatKit` behind a small public API. AGPL-3.0; Element's copyright headers stay in every file.
Why we reuse it and how it fits the app: docs/architecture.md, "Reuse before writing".

| | |
|---|---|
| Upstream | https://github.com/element-hq/element-x-ios, tag in `UPSTREAM.tag` (today `release/26.11.0`) |
| Copied | the paths in `paths.txt` (427 Swift files, about 48,000 lines, plus Compound, strings and assets) |
| Our edits | `patches/` (one patch per upstream file, 13 today) and `Shim/` (our own files) |
| App side | `Adapter/ElementXChatScreens.swift`, the one file the app target compiles |

## The layout

```
Vendor/ElementX/
  UPSTREAM.tag            the release tag the copy comes from
  paths.txt               every copied path; "!path" leaves a file or folder out
  strip-previews.py       removes SwiftUI previews and mock-only extensions while copying
  patches/*.patch         our edits to upstream files, one per file, applied after copying
  ElementX/, compound-ios/  the copy (never edit by hand without saving a patch)
  Shim/                   our own code inside ChatKit: public API, screens, stand-ins
  Adapter/                our code in the app target: implements the app's ChatScreenProviding
```

## How to change it

- **Re-sync** (a newer Element X release, or after editing `paths.txt`):
  `scripts/sync-elementx.sh [release/26.12.0]`. It clones the tag without Git LFS, copies the
  listed paths, strips previews and applies `patches/`. A patch that no longer applies stops the
  run and names itself; fix that file by hand, then save. Review the result as a diff of
  `Vendor/`, build, and run the app before you commit.
- **Edit an upstream file:** change it under `Vendor/ElementX/ElementX/...`, then
  `scripts/sync-elementx.sh --save-patches`. Never edit `patches/` by hand.
- **Check:** `scripts/sync-elementx.sh --check` fails if the copy differs from tag plus patches.
  CI runs it on every push.
- **Changing `strip-previews.py`:** save patches first, change the script, sync. The script
  refuses to save patches after the strip script changed, because the patches would then
  record the stripping as our edits.

## The rules we follow

**A package more than one target links is embedded in the app.** ChatKit, the app and the
notification extension all link MatrixRustSDK, and ChatKit links SwiftOGG's Opus and Ogg. Each
such dynamic package gets `embed: true` (or a plain dependency) on the App target in
project.yml. Without it the simulator still runs, because Xcode's build folder is on the search
path, but the archive misses the framework and Apple rejects the build ("Library missing").

**Shim before patch.** Where upstream code names something we left out, we add a small file of
the same name in `Shim/` (a no-op analytics service, location views that open Apple Maps,
settings with threads on) instead of editing the upstream file. Every patch is a merge conflict
waiting for the next release; a shim is not.

**Hide, do not delete.** Code that needs only small open-source packages stays and is hidden in
the UI (voice messages, polls). Code that needs an outside service or a large package is left
out (calls, maps, crash reporting, analytics) and replaced by a shim.

**Upstream's app stays out.** Element X's coordinators, flows, settings and services that run
the whole app are not copied. `Shim/ChatKitServices.swift` gives the views a client proxy and a
user session cut to what they read; Element X's own SDK wrappers (room proxy, timeline
controller, media provider) do the rest.

## Our edits to upstream files

| Patch | Why |
|---|---|
| `compound-ios/Package.swift` | Compound's snapshot tests are not copied; their target and dependency go |
| `Other/Extensions/Bundle.swift` | `Bundle.app` means ChatKit's bundle, where the strings and assets are; Element X's meaning stays as `hostApp` |
| `Other/Pills/PillAttachmentViewProvider.swift` | a preview-only mock in a non-preview code path |
| `Other/Pills/PillView.swift` | others' mentions in soft teal (`MentionPillColors`), not a dark badge |
| `Screens/Timeline/View/Style/TimelineStyler.swift` | messages as rows in the design's Slack style (`Shim/TimelineRowStyler.swift`), not bubbles |
| `Screens/Timeline/View/ItemMenu/TimelineItemMenuActionProvider.swift` | no Forward and no Pin in the message menu |
| `Screens/RoomScreen/ComposerToolbar/View/RoomAttachmentPicker.swift` | the + menu offers text formatting, photos, camera and files: no polls |
| `Screens/RoomScreen/ComposerToolbar/View/ComposerToolbar.swift` | no voice-message record button (the send button stays, greyed while empty); the placeholder and the "not encrypted" note come from the screen (environment values in `Shim/ChatScreens.swift`) |
| `Screens/Timeline/View/Supplementary/TimelineReactionsView.swift` | a preview container built on mocks |
| `Services/Client/ClientProxyProtocol.swift` | the protocol cut to the members the views use; `Shim/ChatClientProxy` implements it |
| `Services/Room/JoinedRoomProxy.swift` | `reportUtds: false`: no encryption, so no undecryptable events and no hook to report them |
| `Services/Session/UserSessionProtocol.swift` | without calls, notifications and app hooks |
| `Services/Timeline/TimelineItemProxy.swift` | without the SDK mocks import and a mock send handle; hands each local echo's upload progress to `Shim/ChatUploadProgress.swift` |

## Left out (paths.txt, "!" lines) and what replaces it

| Element X part | Here |
|---|---|
| Room screen container (calls, pinned messages, knock requests, identity warnings) | `Shim/ChatScreens.swift`, `ChatRoomCoordinator` and `ChatRoomScreen` on the same view models |
| Location and live-location views (MapLibre, needs a map key) | `Shim/LeftOut.swift`: a line that opens Apple Maps |
| Element Call | no call buttons; a no-op widget driver keeps the room proxy compiling |
| Analytics (PostHog) and timing (Sentry) | `Shim/Analytics.swift`: records nothing |
| Bug reports, keychain, device model, UI-test helpers, test fixtures | not needed by the views |

## Looks

Our views (rows, avatars, thread summary, room header) read `ChatKitStyle.current`; Element X's
views read Compound's tokens, which `ChatKitTheme.apply(_:)` recolours from the same style. The
app builds the style from its theme file (`Adapter/Theme+Chat.swift`), so design feedback
changes App/Sources/Theme.swift and nothing here.

## Still to do

- The rich-text editor package stays linked: the composer is built around it, and removing it
  means patching the composer and its view model in about ten places for no visible gain.
  The formatting entry is gone from the + menu, so it is never switched on.
- Membership changes ("4 Änderungen im Chat") still show as collapsed rows.
- A thread list across rooms for the app's Threads tab (`ThreadListService` per room is vendored).
