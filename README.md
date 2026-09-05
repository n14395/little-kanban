# Little Kanban

A Kanban board for macOS and iOS. Many boards, one global Inbox, one file — with
three surfaces over the same data: a Mac window, an iPad split view and an
iPhone screen.

Built in SwiftUI, offline-first, with optional iCloud sync.

## Features

**Boards**
- Multiple boards, each with its own columns, colours and icon
- Columns are data — add, rename, recolour, reorder, delete — with optional
  work-in-progress limits
- A global Inbox for capture-now-file-later, shared across every board
- Cards with notes, sub-task checklists, labels, four priority levels and due dates
- Drag and drop between columns, boards and the Inbox, on all three surfaces
- Full undo/redo for every mutation, and a per-card activity history

**Finding things**
- Ranked search across every board at once
- Seven built-in saved views (Today, Upcoming, Due this week, Recently updated,
  and more), plus custom views built from field/comparator rules
- Archive for finished work, and a Trash that holds deleted cards, columns and
  boards for 30 days

**Making it yours**
- 20 built-in themes plus a theme editor, with 17 bundled font families
- Light/dark override, adjustable chrome scale, and 29 alternate app icons on iOS

**System integration**
- Widgets: board overview, single column, Inbox, and saved view
- Share extension — send text or a link from any app straight to the Inbox
- App Intents and Shortcuts support, deep links, Handoff and Spotlight
- Due-date reminders through local notifications
- macOS: menu bar quick-add, launch at login, native menu bar and shortcuts
- Export and import as JSON or Markdown, with rolling local backups

**Sync**
- Optional iCloud sync over CloudKit, private database, same-person-multi-device
- Everything works fully offline with sync switched off

## Requirements

- Xcode 26 or newer
- macOS 26 / iOS 26 deployment targets
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Building

```sh
xcodegen generate      # writes LittleKanban.xcodeproj from project.yml
open LittleKanban.xcodeproj
```

`project.yml` is the source of truth; `LittleKanban.xcodeproj` is generated and
git-ignored. There are no filesystem-synchronized groups, so **new files need
`xcodegen generate` before they compile** — a file that isn't regenerated into
the project is a file in no target.

From the command line:

```sh
xcodebuild -project LittleKanban.xcodeproj -scheme LittleKanban \
  -destination 'platform=macOS' build

xcodebuild -project LittleKanban.xcodeproj -scheme LittleKanban \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

If `xcode-select -p` points at the Command Line Tools, prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

A first launch with no board file opens the starter picker. Pass
`-LittleKanbanSkipFirstRun YES` to get past it; `DEBUG` builds read several
other launch arguments for opening a surface directly (see [DESIGN.md](DESIGN.md)).

## Testing

Unit tests use [Swift Testing](https://github.com/swiftlang/swift-testing) and
run from the app's own scheme on either destination:

```sh
xcodebuild test -project LittleKanban.xcodeproj -scheme LittleKanban \
  -destination 'platform=macOS'

xcodebuild test -project LittleKanban.xcodeproj -scheme LittleKanban \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Roughly half the view code sits behind `#if os(macOS)` / `#if os(iOS)`, so a
green macOS run says nothing about iOS — run both. Use
`xcrun simctl list devices available` to pick a simulator that exists.

UI tests are XCUITest on a scheme of their own, iOS simulator only:

```sh
xcodebuild test -project LittleKanban.xcodeproj -scheme LittleKanbanUITests \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

Every test runs against an in-memory store or a temp directory, never the real
board file.

## Project layout

```
project.yml            XcodeGen manifest — targets, plists, entitlements
build.sh               release build: .app, .dmg, signing, notarization
DESIGN.md              the long-form design and rationale document
Sources/
  App/                 app scene, root size-class switch, menu bar, first run
  Model/               tasks, boards, columns, labels, priorities, due dates,
                       saved views, drag payloads, App Intents
  Store/               BoardStore (all state and mutations), the file format
                       and its migrations, CloudKit sync, notifications
  Theme/               palette, typography, themes, appearance
  Shared/              the board itself, plus every view both platforms draw
  Mac/                 window chrome, status bar, menu bar extra, launch at login
  IOS/                 the iPhone surface and the iPad split view
  Widgets/             what the app and its extensions share
  WidgetExtension/     the four widgets
  ShareExtension/      the share sheet
  Capture/             the pending-capture handoff between them
Tests/                 Swift Testing suites
  Fixtures/            older board files, kept to migrate against
UITests/               XCUITest, iOS simulator only
Resources/             assets, fonts, string catalog, entitlements, plists
Tools/                 app icon, symbol catalogue and chime generators
```

`BoardStore` holds all state and every mutation. Views read it and call it;
nothing else mutates a board.

## Data and sync

The board is a single JSON file at
`~/Library/Application Support/LittleKanban/board.json` on both platforms, at
format version 16. Older files migrate forward on read; corrupt or
newer-than-this-build files are quarantined rather than overwritten, and rolling
backups are kept alongside.

iCloud sync mirrors the same board into CloudKit's private database via
SwiftData. It is enabled through the `-CloudKit` entitlement files named in
`project.yml`; pointing the macOS `CODE_SIGN_ENTITLEMENTS` line back at
`Resources/LittleKanban.entitlements` turns it off and leaves the app on the
local store, with no other changes needed.

Sync is same-person-multi-device. There is no sharing or collaboration.

## Release builds

```sh
./build.sh                 # build/LittleKanban.app
./build.sh --dmg           # …and package it
./build.sh --sign          # …Developer ID sign, notarize and staple
./build.sh --publish v1.0  # …tag and cut a GitHub release
./build.sh --help
```

Flags combine. The app icon and the SF Symbol catalogue are generated rather
than checked in — see `Tools/`.

## Localization

Every user-facing string goes through `String(localized:)` or `Text(_:comment:)`
and lands in `Resources/Localizable.xcstrings`. Only English ships today, but
the layout mirrors for right-to-left and nothing user-visible is hardcoded.
Refreshing the catalog requires building *both* platforms — see
[DESIGN.md](DESIGN.md) for the command.

## Design notes

[DESIGN.md](DESIGN.md) is the long-form companion to this file: why each surface
is laid out the way it is, how drag and drop resolves, what the sync layer will
and won't merge, what every test suite covers, and the decisions that were
considered and rejected. Read it before changing behaviour.

## Fonts

17 families are bundled under the SIL Open Font License; the license files are
in `Resources/Fonts/`. They are registered on first use rather than at launch.
Delete the folder and every theme falls back to a system face.
