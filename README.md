# Simple Kanban

A Kanban board for macOS and iOS — one shared board, two native surfaces.

Built in SwiftUI from the Claude Design spec archived in
`simple-kanban design spec.zip`.

## Requirements

- Xcode 26 or newer (developed against Xcode 27.0 / SDK 27)
- macOS 26 and iOS 26 deployment targets — the app uses the native
  Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

```sh
xcodegen generate      # writes SimpleKanban.xcodeproj from project.yml
open SimpleKanban.xcodeproj
```

`SimpleKanban.xcodeproj` is generated and git-ignored; `project.yml` is the source of
truth. One multiplatform app target builds both destinations.

From the command line:

```sh
xcodebuild -project SimpleKanban.xcodeproj -scheme SimpleKanban -destination 'platform=macOS' build
xcodebuild -project SimpleKanban.xcodeproj -scheme SimpleKanban \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

If Xcode is installed but not selected (`xcode-select -p` points at the
Command Line Tools), prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Layout

```
project.yml            XcodeGen manifest — target, plist, entitlements
Sources/
  App/                 SimpleKanbanApp scene, RootView platform switch
  Model/               TaskItem, ActivityEntry, CalendarDay, DayClock, BoardColumn,
                       LabelDef, Priority, DueDate, SeedData
  Store/               BoardStore — all state and mutations; BoardSnapshot + BoardFile —
                       the saved file; BoardMigration — the shapes older files were written in
  Theme/               Palette (design tokens), Typography, SwatchColor
  Mac/                 Sidebar, toolbar, board, columns, cards, inspector
  IOS/                 Header, pager, cards, tab bar, drawer, detail sheet
  Shared/              Chips, checklist, label/priority/due/accent pickers, flow layout, hairlines
Tests/
  Fixtures/            board-v1.json — a real v1 board, kept to migrate against
Resources/
  Fonts/               Manrope + Instrument Serif (OFL), registered on first use
  Assets.xcassets      AccentColor, AppIcon placeholder
```

`BoardStore` is a direct port of the spec's `Component extends DCLogic` class —
same state fields, same transition rules (including the detail that moving a
task into **Done** ticks off its remaining sub-tasks).

## How the design maps to native

The spec is a single web page showing a macOS window and an iPhone side by
side, wrapped in mock chrome. Natively the OS supplies that chrome, so:

| Design | Implementation |
| --- | --- |
| Mock macOS window + traffic lights | Real window, `.windowStyle(.hiddenTitleBar)`; the sidebar reserves the 14pt band the lights occupy |
| Mock iPhone bezel, status bar, home indicator | The device |
| Light/Dark toggle in the page header | Follows the system appearance; both palettes come straight from the spec's theme blocks |
| `--glass` tab bar + `backdrop-filter: blur(20px)` | `glassEffect` inside a `GlassEffectContainer` (the spec's light-mode `--glass` is a self-referential CSS variable and resolves to nothing — Liquid Glass replaces it) |
| Absolutely-positioned label picker | Native `.popover` |
| `animation: sheetUp`, `max-height: 82%` | Native `.sheet` with `.presentationDetents([.fraction(0.82), .large])` |
| HTML5 drag events | `.draggable` / `.dropDestination` with `onDragSessionUpdated` |
| Due chips tinted by matching the strings `"Today"` / `"Thu"` / `"Fri"` | Real calendar days; `DueDate` derives both the chip text and its urgency from the day distance those literals encoded |
| `min-width` on the status segments | Border-box, so the frame wraps the padding; `ViewThatFits` gives the spec's `flex: 1 0 auto` **and** its `overflow-x: auto` fallback |

Deliberate departures from a literal transcription:

- **Type scales with Dynamic Type.** The spec's pixel sizes are used as points
  but declared `relativeTo:` a text style, so the app honours the user's text
  size. Rendering at the default size is unchanged.
- **Shadows are drawn on shapes, not views.** CSS `box-shadow` affects only the
  box; SwiftUI's `.shadow` also blurs the view's *text*. Every shadow here is
  attached to its background shape.
- **Task details are editable.** The spec renders them read-only, but its own
  capture flow creates a task and opens its detail surface — with no way to name
  it. Title, description, priority and due date are all editable now; see
  **Editing** below.
- **Due dates are days, not instants.** `CalendarDay` stores a year, month and
  day, so a task due today still reads "Today" after the device crosses a time
  zone; see **Editing**.
- **A day clock lives in the environment.** One `DayClock` publishes the current
  day and sleeps until the next midnight; every due chip and the "Today" count
  read today from it, so they roll over under a running app.
- **Activity is structured data.** An entry records what happened and is
  rendered into a sentence at display time rather than stored as one; see
  **Activity**.
- **A board file that cannot be read is moved aside before a fresh one is
  seeded.** The design has no failure state for its own storage, and quietly
  overwriting a damaged file is not one worth inventing; see **Persistence**.
- **Backups are kept locally.** A rolling `backups/` folder beside the board,
  because quarantine only rescues a file that fails to decode — not a board the
  app reads perfectly and whose contents are wrong.

## What the spec does not define

These are faithful gaps, not oversights — the design has no behaviour for them:

- **Board and view rows are presentational.** "Website refresh", "Support
  triage", "Upcoming" and friends render exactly as designed but do not switch
  or filter; the spec defines no second board and no view queries. The "Today"
  badge is the exception — it is a real count of tasks due today outside Done.
- **No sync.** The board is saved locally and the design defines no remote. The
  slot the design gave to "Synced just now" reports what the store last managed
  to do with the local file instead (see **Persistence**).
- **No delete.** The design provides no affordance for removing a task.

## Editing

Both detail surfaces — the macOS inspector and the iOS sheet — write straight
through to `BoardStore`, so an edit lands on the board card as it is typed.

- **Title and description** are text fields. A title emptied to nothing is
  restored on blur rather than leaving an unreachable card; a task that has
  genuinely never been named renders as "Untitled".
- **Priority** is a menu whose label is the design's existing dot-plus-name.
- **Due date** is the design's chip, made tappable: Today / Tomorrow / Next week
  shortcuts, a calendar, and Clear.

`due` is a calendar **day** — a `CalendarDay` of year, month and day, written to
disk as `"2026-08-20"` — rather than an instant. A task due today still reads
"Today" after the device crosses a time zone, which an instant normalised to some
midnight does not survive. `DueDate` derives the chip text ("Today", "Fri",
"Next week", "Last week", or a short date beyond a fortnight) and the urgency
colour from how many whole days away it is, and VoiceOver gets the unambiguous
form ("Overdue, Monday 18 August") — the colour that separates last Monday from
next Monday is not something it can read out.

Nothing on that path reads the clock. Today is passed in, from the `DayClock` in
the environment: it publishes the current day and sleeps until the next midnight
— one wake a day, never a ticking timer — and recomputes when the scene becomes
active or the time zone changes. So a chip reading "Today" at 23:59 reads
"Yesterday" at 00:01 without a relaunch, and a test can name whatever day it
likes.

`SeedData` stores the day offsets the spec's literals implied, so the seed board
keeps the design's colours whatever day it is run — only the weekday *names*
track the real calendar.

### Activity

The feed is live rather than static text. Moves, renames, description changes,
priority and due-date changes, label add/remove and new sub-tasks all append an
entry, newest first, and timestamps age ("20m ago", "2h ago", "3d ago").

An entry stores *what happened* — an `ActivityEntry.Kind` case plus whatever its
sentence needs — and the sentence is rendered at display time, so history written
under one language reads correctly under another. `moved`, `labelAdded` and
`labelRemoved` carry the column or label *name* beside its key: an entry is a
historical record and must still read correctly once the thing it names has been
renamed or has gone. Entries from a build that wrote finished English survive as
`.legacy` and are shown verbatim — re-deriving them would be a guess.

Text fields log **once per editing session**, not once per keystroke:
`beginEditing` snapshots the value on focus and `endEditing` compares on blur.
A session is keyed by (surface, task, field), so the macOS inspector and the iOS
sheet editing the same title cannot share — and corrupt — one before-value, and
pointing a surface at another card closes the session against the card that was
actually being edited. The due-date popover's whole lifetime is one session:
trying three dates in the calendar before settling on a fourth writes one entry,
not four. Naming a task that was created untitled is not logged as a rename —
"Created" already says it.

## Search

Search is multi-token AND rather than a phrase match, so "drag columns" finds a
title with the two words apart. Each token is matched against a task's title,
description, code and label keys, and both sides are folded case- and
diacritic-insensitively — "cafe" finds "Café". The folded text is memoised per
task and stamped with `updatedAt`, so a keystroke re-filters the board without
re-folding it.

## Persistence

The board is saved as one JSON document — `BoardSnapshot`, written by
`BoardFile` to `Application Support/SimpleKanban/board.json`. On macOS the app
is sandboxed, so that resolves inside
`~/Library/Containers/com.simplekanban.SimpleKanban/Data/`.

A document rather than a database on purpose: `BoardStore` holds plain value
types, so the whole board encodes in one pass and the port of the spec's logic
is untouched by it. If sync ever matters, this is the layer to replace.

- **Writes are debounced 500ms.** Typing a title mutates the board on every
  keystroke; the file is written once the typing stops. The debounced task holds
  the snapshot *value*, the file and the write gate rather than the store, so an
  edit made just before the store goes away still reaches the disk — and the
  encode and the write happen off the main actor, since they are the two things
  in a keystroke's path that grow with the board. `saveNow()` skips the debounce
  for the two moments it would not survive — `scenePhase` leaving `.active` on
  iOS, and `NSApplication.willTerminateNotification` on macOS, which ⌘Q does not
  route through `scenePhase` — and stays synchronous, because at quit the
  ordering genuinely matters. Each write carries a generation, so a background
  write overtaken by the quit-time one is dropped rather than undoing it.
- **Writes are atomic**, so a crash mid-write leaves the previous board intact.
- **A file that cannot be read is moved aside before anything replaces it.**
  Damaged JSON becomes `board.corrupt-<stamp>.json`; a `version` newer than this
  build understands becomes `board.from-newer-version-<n>-<stamp>.json`; only
  then is a fresh board seeded. If even the move fails, saving is **blocked**
  until the launch alert is acknowledged — the only copy of the user's work is
  still sitting at `board.json`, and a write would land on top of it. A file
  that is simply absent is not a failure and leaves nothing behind.
- **Older files are migrated, not guessed at.** `BoardSnapshot.currentVersion`
  is 2. The version is read out of the raw JSON *before* anything is decoded,
  because synthesised `Codable` throws `keyNotFound` for a key the older shape
  never wrote — a property default does not make a field backward-compatible.
  `BoardMigration.swift` holds the frozen v1 shapes and the v1 → v2 conversion
  (string ids become UUIDs, `due` becomes the day it always meant, each rendered
  sentence is kept as `.legacy`), and the pre-migration bytes are copied to
  `board.v1-<stamp>.json` first: a migration is the one moment the old shape
  stops existing anywhere. `Tests/Fixtures/board-v1.json` is a real v1 file kept
  to migrate against.
- **Rolling backups.** The live file is copied to `backups/board-<stamp>.json`
  beside the board when the newest backup has aged past 15 minutes, and the ten
  newest are kept. Taken on the debounced path only, never at quit.
- **Failures reach the user.** `BoardFile.write` throws rather than logging —
  `OSLog` is not a user interface, and an app that has silently stopped saving
  looks identical to one that is working. The store keeps the last error, the
  macOS status bar shows it — and when there is none, how long ago the board last
  saved — and a load failure raises an alert at launch naming the file the
  damaged board was kept as.
- **`nextSerial` is saved.** Without it a new session restarts at NW-140 and
  issues codes that collide with tasks an earlier session already created.
- **Session state is deliberately excluded** — selection, drafts, search query,
  current tab and drag state belong to a sitting, not to the board.

`BoardStore(file: nil)` is an in-memory store that never touches the file, which
is what previews and tests should use.

### Identity and timestamps

A task's `id` is a `UUID`. `code` — "NW-118" — is the human-facing label printed
on the card: sequential per board, unique only within it, and meant to be read
out loud. Nothing keys off it, so renumbering or importing a task cannot break a
reference. v1 files stored string ids (`"t1"`) that nothing referred to, so the
migration mints fresh UUIDs for them.

Every task also carries `createdAt` and `updatedAt`. `updatedAt` is stamped
centrally by every mutation, and doubles as the stamp on the search cache; a
migrated task takes both from its own activity feed, which is the only evidence a
v1 board carries about when anything happened.

### Accent

`AccentTheme` was fully wired in the design's palette but had no UI. There is a
swatch row in the macOS sidebar and the iOS drawer now, and the choice is saved
with the board.

`SwatchColor` keeps literals as `.rgb(hex, opacity:)` rather than a built
`Color` — that is what makes a user-created label encodable, since `Color` is
not `Codable`.

## Debug launch hooks

`DEBUG` builds read launch arguments so a surface can be opened directly,
without scripting taps:

```sh
xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenSheet NW-118
xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenDrawer YES
xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanTab search
```

The sheet argument takes either a task's `code` or its UUID, matched
case-insensitively. `SeedData` exposes the seed ids as named statics
(`SeedData.dragAndDropTaskID` and friends) so a test can address one directly.

## Naming

The product name, bundle identifier and display name live in `project.yml`
(`PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleDisplayName`). The Xcode
project, target and scheme are `SimpleKanban` (no space, so command-line
invocations stay quote-free); the built app is `Simple Kanban.app`.

The wordmark shown in the iOS navigation drawer is in
`Sources/IOS/PhoneNavDrawer.swift`.

## Fonts

Manrope and Instrument Serif are bundled under the SIL Open Font License
(see `Resources/Fonts/OFL-*.txt`) and registered by `FontRegistry` on first use
rather than at launch: `hasCustomFonts` is a `static let` whose initialiser does
the registering, so it runs exactly once, under the runtime's own lock, the first
time anything asks for a font. Delete the folder and the app falls back to the
system faces.
