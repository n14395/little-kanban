# Simple Kanban

A Kanban board for macOS and iOS — many boards, one global Inbox, one shared
file, three surfaces over one board: a Mac window, an iPad split view and an
iPhone screen.

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
truth. One multiplatform app target builds both destinations, with the widget
extension — `SimpleKanbanWidgets`, also multiplatform — embedded in it.

**New files need `xcodegen generate` before they compile.** The project has no
file-system-synchronized groups, so a file written and not regenerated into is a
file in no target.

From the command line:

```sh
xcodebuild -project SimpleKanban.xcodeproj -scheme SimpleKanban -destination 'platform=macOS' build
xcodebuild -project SimpleKanban.xcodeproj -scheme SimpleKanban \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

If Xcode is installed but not selected (`xcode-select -p` points at the
Command Line Tools), prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The unit tests run from the same scheme on either destination — see **Tests**.
`build.sh` wraps the release path instead: it produces `build/SimpleKanban.app`,
and `--dmg`, `--sign` (Developer ID, notarize, staple) and `--publish vN.N` take
it the rest of the way. `./build.sh --help` prints the lot.

Two things are generated rather than checked in by hand and are re-run when what
they are drawn from changes: `swift Tools/make-app-icon.swift` writes the app
icon, and the String Catalog is synced from the compiler's own extraction — see
**Language and direction** for the command, which needs a build of *both*
platforms.

A build run against a machine with no `board.json` comes up on the first-run
picker. `-SimpleKanbanSkipFirstRun YES` gets past it; see **First run**.

## Layout

```
project.yml            XcodeGen manifest — targets, plist, entitlements, exported drag types
build.sh               release build: .app, .dmg, signing, notarization, GitHub release
Tools/
  make-app-icon.swift  draws the app icon: all eleven PNGs *and* the appiconset's
                       Contents.json, so a slot and its image cannot drift apart
  simple-kanban-icon-4f.svg
                       the design it transcribes, kept beside it so the numbers
                       in one can be checked against the other
Sources/
  App/                 SimpleKanbanApp scene, RootView's size-class switch and undo-manager
                       handover; BoardCommands — the menu bar, on both platforms, and AppWindowState;
                       FirstRunView — the starter picker a first launch comes up on;
                       AboutView and UpdateChecker — the macOS About window's panel;
                       AppIconInstaller and WidgetKeeper — the two facts about the app
                       that are kept in step from the one place that can see the store,
                       the clock and the appearance at once
  Model/               TaskItem, TaskPlacement, Board, BoardColumn, ActivityEntry,
                       CalendarDay, DayClock, LabelDef, Priority, DueDate, SavedView,
                       TaskTransfer, AppCommand — the shortcut vocabulary, SeedData;
                       TaskIntents — deep links, Handoff, Spotlight and App Intents
  Store/               BoardStore — all state and mutations; BoardSnapshot + BoardFile —
                       the saved file; BoardMigration — the shapes older files were written
                       in; SyncSchema + BoardSyncStore — the same board as SwiftData
                       records, and the CloudKit mirroring on top of them;
                       CloudKitEntitlement — whether this build may ask for a container
                       at all, which is a crash rather than an error to get wrong;
                       NotificationScheduler — due-date reminders; WidgetPublisher —
                       the fourth follower a save carries, which writes the widgets' digest
  Theme/               Palette (design tokens), Typography, SwatchColor, AppAppearance —
                       the light/dark override, here rather than beside its settings row
                       because the widgets read it too
  Widgets/             What the app and its widget extension both compile: WidgetDigest —
                       the flat, capped rendering of what the widgets draw; WidgetShare —
                       the App Group and the widget kinds; WidgetDigestFile — the one
                       file that crosses the fence; AppLink — every URL that names a
                       place inside the app
  WidgetExtension/     The four widgets and nothing else — excluded from the app's target
                       in project.yml, and under Sources/ so the suite's source rules
                       still apply to it
  Mac/                 What only a window has: the root layout, the status strip, the
                       shortcuts sheet, the due-date sheet and the menu bar extra
  IOS/                 PhoneRootView — header, pager, cards, tab bar, drawer, Inbox, detail
                       sheet; PhoneColumnPage — one column of that pager, cards and the
                       ground around them; PhoneCardStack — the container both it and
                       the Inbox sheet draw their cards in, which is a column's stack
                       rather than a `List` so that a drop has somewhere to land;
                       PadRootView — the desk's three panes in a split view
  Shared/              The board itself — scroller, column, card, composer, keyboard map
                       — plus BoardSettingsView, a board's name, colour and columns
                       on every platform
                       — plus InboxPanel, the global Inbox standing beside it
                       — plus the sidebar, the toolbar, the inspector, chips (label, due,
                       column, count), checklist, completion toggle, label manager, empty
                       states, activity feed, flat task list,
                       label/priority/due/accent/dot/move-to pickers, board destination
                       menu, flow layout, hairlines; settings, the export/import
                       documents with the panels that present them, and the two
                       accessibility helpers every surface goes through — ScaledChrome
                       (chrome that grows with Dynamic Type) and ReducedMotion
Tests/                 Swift Testing suites — model, store, boards, columns and the
                       Done one, placement, editing sessions, undo, persistence, search and
                       its scoping, saved views, the archive, migration, day rollover,
                       drag payloads and where a drop may land, touch metrics, selection
                       and the bulk commands, the shortcut vocabulary, board focus,
                       export/import, backups, notifications, deep links, App Intents,
                       preferences, the first-run templates, the built bundle, the
                       localisation rules, the widgets' digest and the links they are
                       wired with, five hundred cards, and the joins between all
                       of those and the app
  Fixtures/            board-v1*.json … board-v5.json — real older boards, kept to migrate against
UITests/               XCUITest, iOS simulator only, on a scheme of its own — the drag
                       between the Inbox panel and the board, where a card dropped on
                       a column's ground lands on either idiom — and that a card
                       dropped *below* a list lands at the foot of it — the board
                       settings sheet holding a board and its columns and asking
                       before it trashes one, what the
                       phone's board menu holds and no longer holds, the task code
                       no longer at the head of the editor, the leading-edge
                       swipe that opens the drawer and the source list, the
                       column strip's portrait-only rule, the tab bar riding in
                       the header on its side, cards that no longer swipe open, the detail
                       sheet stopping short of the top, the "+" raising no panel
                       behind it, and Settings showing one subject at a time:
                       which recognizer wins a pan, what a size class draws, where
                       a control *lands*, what a row does under a finger, how tall
                       UIKit made a sheet, what is left standing once a sheet is
                       dismissed, and which of seven panes is built, are the
                       things no unit test can reach
Resources/
  Fonts/               Manrope + Instrument Serif (OFL), registered on first use
  Assets.xcassets      AccentColor; AppIcon — one iOS slot and ten macOS renditions,
                       all written by Tools/make-app-icon.swift; LaunchBackground —
                       the colour UILaunchScreen names, in both schemes
  Localizable.xcstrings  the String Catalog every user-facing string extracts into
  PrivacyInfo.xcprivacy  the required-reason API declarations a submission is read for
  SimpleKanban.entitlements  sandbox, user-selected files, the network client the
                       update check needs, and the App Group the widgets read through —
                       spelled with the team id on macOS and without it on iOS, which is
                       why there are five of these files and not one
```

`BoardStore` is a direct port of the spec's `Component extends DCLogic` class —
same state fields, same transition rules (including the detail that moving a
task into **Done** ticks off its remaining sub-tasks).

## How the design maps to native

The spec is a single web page showing a macOS window and an iPhone side by
side, wrapped in mock chrome. Natively the OS supplies that chrome, so:

| Design | Implementation |
| --- | --- |
| Mock macOS window + traffic lights | Real window, `.windowStyle(.hiddenTitleBar)`; the board header *is* the chrome, with the lights sitting on its row — see **The header is the title bar**. The sidebar reserves the band they occupy, and with the sidebar hidden the toolbar takes a 68pt leading inset instead |
| Mock iPhone bezel, status bar, home indicator | The device |
| Light/Dark toggle in the page header | Follows the system appearance; both palettes come straight from the spec's theme blocks |
| `--glass` tab bar + `backdrop-filter: blur(20px)` | `glassEffect` inside a `GlassEffectContainer` (the spec's light-mode `--glass` is a self-referential CSS variable and resolves to nothing — Liquid Glass replaces it) |
| Absolutely-positioned label picker | Native `.popover` |
| `animation: sheetUp`, `max-height: 82%` | Native `.sheet` at `.presentationDetents([.fraction(0.8)])` — four fifths, near enough the spec's figure. It shrinks every control inside it by 4%, which is a cost this app now takes deliberately; see **Touch targets** |
| HTML5 drag events | `.draggable` / `.dropDestination` with `onDragSessionUpdated`, over the app's own `TaskTransfer` type rather than loose text; see **Drag and drop** |
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
- **Every board change is undoable.** The design has no undo and no confirmation
  on anything, which is a fine pairing only while nothing can be lost. ⌘Z is the
  system's own `UndoManager`, so it is the Edit menu on macOS and shake-to-undo
  on iOS; see **Undo**.
- **Tasks can be deleted, and completed without being dragged.** Both are
  affordances the design simply does not draw. Delete asks nothing first —
  undo, rather than a dialog people learn to dismiss unread, is the safety net.
- **Sub-tasks and labels are editable, not append-only.** The spec can add a
  sub-task and tick it, and add a label and apply it, and that is the whole of
  it. Rows are renamed, deleted and reordered in place; labels are renamed,
  recoloured and deleted board-wide; see **Editing**.
- **A title is one line.** The design's field wraps, so Return typed a newline
  into a string the card layout has no room to draw. Return commits instead, and
  anything pasted in has its whitespace folded flat before it reaches the card.
- **Cards only drag where the rows on screen are the board's own order.** A drop
  resolves against the whole array, so under a stale slice a card lands where
  nobody can see it, and in a saved view — which draws no columns and may impose
  an ordering of its own — it lands in a column the user is not even looking at;
  see **Drag and drop**.
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
- **Every control is a finger wide on touch.** The spec is drawn for a pointer,
  so its swatches are 28pt and its checklist boxes 30pt; the iOS build claims
  44pt for each of them without redrawing any of it. See **Touch targets**.
- **Nothing renders as blank space.** Every list in the design is drawn with
  content in it, so an empty column, an empty board, a search that matched
  nothing, an empty saved view and an unselected inspector had no appearance at
  all. Each says which kind of empty it is and offers the one thing worth doing
  about it; see **Empty states**.
- **The Inbox is a panel beside the board, and a row under Views — but never the
  board's first column.** The design draws it as a column, and with a single
  board that reads fine. The Inbox is global — a quick capture must never have
  to pick a board first — so drawing it inside one board's strip would say it
  belonged to that board, and it would have to be drawn identically inside every
  other. It was a destination for a while, which was worse in the other
  direction: picking it took the board away, and the one list you reach for
  *while* working on a board was the one list you had to leave the board to see.
  It is now two things that do not get in each other's way: `InboxPanel`, a
  column-wide strip between the source list and the board for working *with* the
  Inbox, and a `SavedView` row at the head of Views for reading it full width.
  The phone was the last surface where it was still a destination, and is not any
  more: `PhoneInboxSheet` slides it up over the board — see **The iPhone**.
  See **The Inbox is global**.
- **"Move to" is the board's columns, and the board menu above it is everything
  else.** The spec's control lists the workflow only (`COLS` rather than
  `ALL_COLS`), which on the phone — where it is the only route off a board —
  made filing a card a one-way door. The Inbox led the segments for a while to
  fix that; the fix now lives in `BoardDestinationMenu`, which sits directly
  above the picker on both surfaces and lists the Inbox first. That is the truer
  split: the menu answers *which board*, and a card in the Inbox is on none;
  the picker answers *where on it*, and the Inbox is not a place on a board.
  Which is why **the picker disappears once the menu reads Inbox** — there is no
  board left for the segments to be the columns of. They used to fall back to
  whichever board was on screen, so that filing a captured card was one tap on a
  column rather than a board and then a column; it read as a lie about where the
  card was — a row of columns it was not in, none of them marked — and the menu
  above files it in one go regardless.

  **Done is not one of the segments.** It is the board's last column and the one
  place a tick already sends a card, and the completion button sits on the same
  surface a few points above this control — so a segment for it is a second way
  to do the one thing here that is not really a move, and it is the segment
  nobody drags a card to. A card that *is* done therefore has no segment marked,
  which is what the control already does for a card on another board and reads
  the same way: nothing here claims to be where it is. Pressing any segment moves
  it out of Done, which is what un-ticking it would have done. The **Move
  Column** menu still lists every column, because a menu opened on demand is a
  complete answer to "where can this go" rather than a row competing for width.
- **A card away from its place says where it is.** The design only ever draws a
  card under its own heading. The saved views and the iOS Search tab draw cards
  from anywhere, where the column is the one thing the card no longer says, so
  those carry a column chip — and an unfiled card gets an "Inbox" chip rather
  than none, because absence is not readable in a list that mixes the two. The
  Inbox's own surfaces are the exception and drop the chip: every card in one is
  in the Inbox, so the chip would say nothing; see **Saved views and the
  archive**.
- **Work can be filed away rather than only finished or deleted.** The design's
  Done column is where cards go and stay, so a board in use for a month is
  mostly history. The Archive keeps them in the file and off the board; see
  **Saved views and the archive**.
- **Everything the app can do has a name, a menu item and a key.** The design
  draws no menu bar, so the app shipped SwiftUI's defaults — which went on
  advertising New Window on the ⌘N a toolbar button had quietly taken for New
  Task. One vocabulary feeds the menu bar, the board's key handlers and a
  shortcuts reference now; board cards take focus and move under ⌥←/→, and every
  one of those commands is a VoiceOver action as well as a key, which is the
  first non-drag way this board has had of moving a card. See **Selection,
  commands and shortcuts**.
- **The phone turns.** The spec draws one portrait screen and the plist locked
  the phone to it. Landscape shows three columns at once, which is a Kanban
  board doing the thing a Kanban board is for; see **Gestures and haptics on
  iOS**.
- **The iPad gets the desk, not the phone.** The spec draws two devices and the
  root picked between them with `#if os(macOS)`, which made every iPad a very
  large phone. The layout is chosen by the idiom *and* the window's width now —
  a Max-class iPhone in landscape is a regular size class and is still a phone —
  and the board,
  the sidebar, the toolbar and the inspector moved into `Sources/Shared/` so the
  iPad composes the same views rather than a third copy of them; see **The
  iPad**.

## Touch targets

Apple's minimum is 44x44pt on touch and the spec's own geometry is smaller than
that in several places, so the rule is that **the claim grows and the drawing
does not**. Widening the circle, the pill or the chip would be a different
design; widening the region that hit-tests to it is not.

A control in `Sources/Shared/` is used by both the macOS inspector and the iOS
sheet and has no `#if os()` to lean on, so it carries the number instead: every
one has a nested `struct Metrics` with its own hit sizes and two presets, `.desk`
for the pointer and `.sheet`/`.drawer` for touch. The touch preset is at least
44; the pointer preset claims exactly what the control draws, or zero — a
`frame(minWidth: 0)` and a `padding(-0)` are exact no-ops, which is what keeps
macOS pixel-identical. `.buttonStyle(.bare)` already puts a `.contentShape(.rect)`
around a button's label, so framing the label at the hit size is the whole fix.

Four details are worth knowing before changing any of it:

- **Where a wider claim would push a neighbour, pull it back.** The checklist
  box claims 44 and hands the difference straight back as negative padding
  (`ChecklistView.boxOverhang`), so the row keeps the height and the text
  position it draws today. Keep the overhang inside the row: hit-testing does
  not follow a view outside an ancestor.
- **Where 44pt targets and the design's gaps cannot both fit a 375pt phone, the
  targets win.** `ColorPickerPopover.Metrics.sheet` sizes its swatch row so four
  still fit across the narrowest phone, and `ThemeBrowserView.Metrics.sheet` keeps
  a 248pt theme tile inside 375 with its own padding either side rather than
  letting the grid scroll sideways. `TouchTargetTests` holds both.
- **A `TextField` is not covered by a frame.** Its editable area is the text it
  draws — around 21pt tall inside a 44pt row — so a frame around it buys
  nothing. The row gets a `.contentShape(.rect)` and an `.onTapGesture` that
  claims focus, which is what makes the whole row edit. `ChecklistView.row`,
  `ChecklistView.addRow` and `LabelManagerView.row` each carry that pair, and on
  the phone `PhoneDetailSheet` puts a `focusCatcher` *behind* each field — behind,
  so a tap on the text still reaches the field and the caret lands where the
  finger did. A filled `.background` drawn over such a catcher needs
  `.allowsHitTesting(false)` or it swallows the taps the catcher is there for;
  `PhoneHeader`'s search pill is the one that does.
- **The accessibility tree has its own frames, and its own way of ignoring you.**
  A field's accessibility element is its text too: `PhoneHeader`'s search field
  published a 309x22 frame inside a 44pt row, and `.frame(minHeight: 44)` did not
  move it — `.contentShape(.accessibility, Rectangle())` is what hands it the row.
  A placeholder is not a name either, so the field carries an explicit
  `.accessibilityLabel`. The checklist's sub-task fields had both faults —
  measured at 289x21 with no label at all — and take the same treatment through
  `ChecklistView.Metrics.fieldHit`, with `fieldOverhang` handing the extra height
  back to the row the way `boxOverhang` does for the toggle. They measure 289x44
  and read "Sub-task, Lift + shadow states" now. And an `Image` among siblings is
  published whatever you do to it: neither `.accessibilityHidden(true)` on the
  symbol nor `.accessibilityElement(children: .ignore)` on the row removed the
  drawer's seven decorative SF Symbols, which stayed *hittable* under Apple's
  catalogue names ("Warning", "Brightness Higher", "Clock With A Circular Arrow").
  `EmptyStateView` had the same leak from inside an `.accessibilityElement(children:
  .combine)`, where an empty Backlog's `tray` published an element called "Inbox" —
  a word from a different part of the app.
  `.accessibilityRepresentation`, which substitutes the subtree outright, is what
  works in both places; the drawer rows read "Today, 1" and the empty state reads
  its headline and message as one sentence with no glyph in it.
- **A field is only as wide as the last time somebody measured it.** The label
  manager's rename rows published 124.7x22.3 and now carry
  `LabelManagerView.Metrics.fieldHit`, the same pair `ChecklistView` uses, for
  124.7x44 on all five rows. The add-column composer held two more of the same
  kind: its Cancel measured 47.3x19.3 and its name field 43.9pt tall, and a 44pt
  frame plus `.contentShape(.accessibility, Rectangle())` takes them to 75.3x44
  and 338x44. `TouchTargetTests` pins both new presets — it could not have found
  either.

`Sources/IOS/` follows the same rule with no `Metrics` to carry it: the platform
views frame their labels at 44 inline, and put `.contentShape(.circle)` on the
`Button` rather than inside its label, because the outer shape is the one that
wins. Where the wider claim would move the drawn shape, it is anchored —
`PhoneHeader`'s hamburger frames at `alignment: .bottomLeading` so the disc keeps
its margin and the target grows into the space above it.

The desk is under the same *accessibility* rule, even though the pointer
never needed the 44pt half of it — a screen reader reads the desk too. The
sidebar's Manage-labels row, both "back to the board" buttons, the new-task and
new-board rows and the add-column tile substitute their subtrees; the column
header's `ellipsis` is hidden instead, because a `Menu` cannot be substituted
without losing the menu. Where a label holds no `Image` at all — the sidebar's
Inbox, board and saved-view rows, whose dot is a `Circle` and not an element —
the smaller fix is enough and reads better anyway: the name is the
`.accessibilityLabel` and the count is the `.accessibilityValue`, so the row is
not *renamed* every time a card is filed. Substituting a subtree does not swallow
a `.keyboardShortcut`, measured — but that measurement was taken while ⌘N still
lived on the toolbar's New task button, and it no longer has a subject: ⌘N is the
File menu's now and no substituted control in this app carries a key of its own
(see **Selection, commands and shortcuts**). Whether substitution keeps a
*context* menu was never measured, which is the other reason the board rows take
the smaller fix: their context menu is the only route Board Settings and the two
reorder items have.

**The detail sheet is the one surface that knowingly renders under 44pt.** A
sheet held at any detent below `.large` is laid out at the full screen width and
then *transformed* — inset 8pt from each screen edge and scaled by
`(width - 16) / width` — so its whole content renders smaller than it lays out.
Measured with the Close button, which is exactly 44pt as drawn:

| Device | Width | `.large` | `.fraction(0.8)` | Factor |
| --- | --- | --- | --- | --- |
| iPhone 17 Pro | 402pt | 44.0000 | **42.2487** | 0.96019 |
| iPhone 17e | 390pt | 44.0000 | **42.1949** | 0.95897 |

`(width - 16) / width` to five places on both, so the arithmetic is the whole
story and it holds for every control in there — Close, Add label, the checklist
toggles, the Move-to chips, Due date and Priority.

**The sheet was `.large` for exactly that reason and is not any more**, because
four fifths is what it was asked for. The factor differs per device, so no
constant inflation of the shared `.sheet` presets clears 44 everywhere; a preset
that did would have to be `44 * width / (width - 16)`, which is 45.82pt on a
402pt phone and 45.96pt on the narrowest iPhone this build runs on. Rounding all
of them up to 46 would clear it — at the cost of every other surface those
presets are shared with. The alternative is not to be a sheet at all: a
`PhoneNavDrawer`-shaped overlay takes any share of the screen without a
transform, which is what `PhoneInboxSheet` is and why. Neither is a smaller
change than the detent, so neither was made on the way past; the 4% is recorded
here and in the source rather than discovered later.

`TouchTargetTests` cannot see any of this — it reads the presets, and the presets
still claim exactly 44. What it does not know is that this one surface is scaled
after the fact. `UITests/DetailSheetHeightTests` pins the height that costs it.

The board itself now carries the pair too. `BoardTaskCard`, `BoardColumnView`,
`BoardScrollView`, `BoardTaskComposer`, `BoardSidebar`, `BoardToolbar` and
`TaskInspector` each have a `.desk` preset holding the numbers that were literals
in `Sources/Mac` and a `.pad` preset that claims 44 wherever the pointer claimed
22, 24, 26 or 34. Two of those numbers are worth knowing about. A `Metrics` that
selects another control's preset — `BoardColumnView.Metrics.pad.emptyState` is
`EmptyStateView.Metrics.sheet` — is still passing metrics, not branching on the
platform, and it is what keeps the inspector's seven sub-controls from needing
seven call-site conditionals. And `FieldHitArea` exists because a `minHeight` of
zero has to mean *nothing at all*: it applies the 44pt frame and the
`.contentShape(.accessibility,)` only when the preset asks for them, so a control
shared with macOS does not quietly reshape its accessibility element there.

`EmptyStateView` is the newest control to carry the pair: its action button is
drawn at the same size on both platforms, and `Metrics.sheet.actionHit` claims
44pt *around* the drawn pill while `Metrics.desk.actionHit` is 0. `ActivityFeed`
and `TaskListMetrics` carry no hit sizes at all — neither has a control of its
own, and a metric that guards nothing is one more number to keep true.

`TouchTargetTests` guards the metrics as constants, because the two defects the
rule was written for — a 28pt swatch and a 30pt checklist box — were both a
constant nobody could see was too small, and a constant is what a later edit
puts back. Its limit is that a constant cannot see a live `TextField`'s area:
both rows above measured 44pt in the suite while the field inside them was live
for 21, and closing that took a coordinate tap on a booted simulator. Anything
about a *rendered* region has to be proved that way rather than read.

## Accessibility

Touch targets are one half of this; the other half is what the app says, what it
says it with, and what happens to the layout when the reader turns the type up.
Four rules, each of which came out of a finding the Accessibility Inspector's
audit made against a running build.

**Nothing is said in colour alone.** Priority used to be a coloured dot: four
tints, one shape, and in greyscale a card said nothing about how urgent it was.
`PriorityDot` now draws a different *shape* per priority — a filled triangle, a
filled disc, a filled square, a ring — which nobody has to turn a setting on to
get, and `PriorityDot.mark(for:)` names the four so the suite can hold them
apart. The suite counts them off `Priority.allCases` rather than off four, so a
priority added without a mark of its own fails there rather than drawing as one
of the others. With
`differentiateWithoutColor` on, the mark on a card adds the word as well; the
picker leaves it off, because there the word is already the row beside it. The
due chip's meaning was entirely in its tint, so under the same setting it takes a
glyph — a tick for done, an exclamation for urgent, a clock for close, and
nothing at all for a date far enough out that the chip is only a date. A mark on
every chip would distinguish nothing. Which way round that flag is read lives in
a view body, where no assertion about a value can reach it, so the suite states it
about the source instead: `differentiateWithoutColor` is never read negated. The
setting only ever *adds*.

**Secondary ink has a floor.** The design's quiet tones run from 0.38 of ink on a
section label to 0.55 on a place chip, and against the surfaces they are drawn on
those read between 2.4:1 and 4.0:1 — under the 4.5:1 WCAG asks of text that size,
and 26 separate audit findings on one iPad screen. Every `foregroundStyle` that
took a fraction of ink now goes through `Palette.inkText(_:)`, which floors the
opacity at `Palette.readableInk`. The call site still passes the design's own
number, so the hierarchy it wanted is still written down and lifts on its own if
the palette is ever re-toned. `AccessibilityContrastTests` walks every tone
against every surface in both schemes. The floor is 0.68 rather than the 0.62 the
arithmetic alone allows: at 0.62 the audit went on reporting the count pill,
whose 11pt digit sits on a second wash of ink and computes to 4.76:1 — a number
anti-aliased type that small does not actually deliver.

**Chrome grows with the type inside it.** A 50pt toolbar, a 232pt source list, a
272pt column and a 372pt panel are all boxes around text that scales, and at AX5
they clipped: column headings truncated to "Bac…", the inspector broke "Priority"
across two lines as "Prio / rity". `ChromeScale` is a `DynamicProperty` that
hands back one multiplier — how much larger the reader's text is than the
default — and every one of those numbers is passed through it. Heights are stated
as **minimums**, so past the cap the container keeps growing on its content;
widths take the cap, because a source list twice its width is most of an iPad.
The two roots and `TaskInspector` share `TaskInspector.widthCap` so the panel and
the slot it sits in grow by the same amount. Three places take the trade the
other way: `LabelChip` and the phone's tab pill hold one line and shrink to it —
"Board", "Inbox" and "Search" are single words with nowhere to break, and the
pill read "Boar / d" — and `ProgressMeter` steps out of the row entirely, because
it is decoration a reader is already hidden from and the count beside it says the
same thing in words.

SF Symbols went with them. `.font(.system(size:))` pins a glyph, so at an
accessibility size the word beside it doubled and the icon did not; `symbolSize(_:weight:relativeTo:)`
is the replacement, and fourteen call sites now use it. C3 asks this of new code;
that sweep is what the old code needed. It caps like `ChromeScale` does, and for
the same reason: past a point the glyph is growing inside a button that has
stopped.

**Reduce Motion is honoured everywhere there is motion.** `.animation(_:value:)`
became `motionAnimation(_:value:)` — the same thing, with the animation dropped
when the reader has asked for less — and every `withAnimation` goes through
`Motion.run(_:reduceMotion:_:)`. A `nil` animation is what SwiftUI reads as "at
once", which is the point: the drawer still opens, the pager still lands on the
column, the board still scrolls the focused card into view. Only the travel goes.
The card's hover lift is the one thing that goes entirely — the shadow still
deepens, because that says where the pointer is rather than moving anything.

### Modals, and the surface behind them

`PhoneNavDrawer` is a hand-rolled `ZStack` overlay rather than a sheet, so it
carries `.accessibilityAddTraits(.isModal)` and moves focus to its title on open.

**It is a list of places and nothing else.** It carried a "this week, N shipped"
card and the accent switcher under the rows; both are gone, which is the trade
the macOS source list made first. The accent is still in Settings, which the
drawer's own `settingsRow` opens, so nothing became unreachable — the meter has
no reader on any surface now, and the note under **Identity and timestamps**
says what became of it.

**Due date reminders went the same way, and were the clearest case of the rule.**
The drawer carried a Reminders section at its foot — a row with the time of day
beside it, opening a `PhoneRemindersSheet` with the switch and the picker on it.
Two things were wrong with that. It was a *preference* in a list whose every
other row goes somewhere the user's work is: boards, views, the Archive, the
Inbox. And it was a second, narrower copy of a pane Settings already had —
Settings ▸ Notifications carries the same switch, the same picker, the same
standing explanation of a refused permission and the same trip to System
Settings, plus the day-before and the overdue-nag switches that the drawer's
sheet never grew. Two surfaces for one preference is two places for it to drift,
and the smaller one was already behind. The sheet is deleted rather than moved:
there was nothing in it Settings did not already draw. Everything below the title still scrolls rather than the
rows being given whatever height is left after something pinned to the bottom:
on a 402x874 phone that was 481pt for 620pt of rows, so the Archive row was
clipped and "Manage labels" sat 59pt past the fold with nothing to say so.

The macOS label manager was reported as invisible to accessibility — no `AXSheet`
under the window, none of its controls anywhere. **That half does not
reproduce.** Driven on macOS 26 through a UI-test bundle: with the sheet up the
window has one `AXSheet` child (its children go 4 → 5), and the sheet publishes
36 buttons, 12 static texts and 5 text fields — 55 elements, every one
`hittable=true`, including all six colour swatches on every row. What *did*
reproduce is the other half: the board behind stayed reachable, with `New task`
answering `hittable=true` under a modal that had taken the pointer away from it.
So the fix is on the presenting side. `LabelManagerSheet` hides the view it is
attached to while it is up, and on macOS the flag is hoisted to `MacRootView`
(`BoardSidebar.isManagingLabels`, a binding in the same shape as
`isNamingNewBoard`) so the whole window goes with it. Measured after: the app's
button count drops from 84 to 39 — the 36 in the sheet plus three — `New task`
and the column menus are gone from the tree, the sheet keeps all 55 of its
elements, and the audit over that state falls from 37 findings to 4.

### What the audit still says

`performAccessibilityAudit` from a UI-test bundle is the same check the
Accessibility Inspector runs. On an iPad Pro 13" in portrait it went from **58
findings to 27** (contrast 26 → 6, clipped text 17 → 5); on macOS the board reads
11, and the label-manager sheet 4. Two categories survive and are understood:

- **`dynamicType`, 16 of them, all on micro-labels.** Every one is text at 11pt
  or below — the uppercase label chips, the count pill, the sub-task badge, the
  section captions — drawn in the bundled Manrope face through
  `.custom(_:size:relativeTo:)`. They *do* scale: a label chip measures 17.5pt
  wide at the default size and 61.5 at AX5. Nothing at 11.5pt or above is
  flagged, which puts the audit's floor between the two; taking it would mean
  raising the design's smallest type, which is a design decision rather than a
  fix.
- **A handful of `textClipped` on views that truncate by construction** — the two
  text fields, a card's note under its line limit, a menu label under
  `lineLimit(1)`. The card's note now gets six lines instead of two at an
  accessibility size, which is the part of that group that was a real defect.

The harness lives in the scratchpad rather than the repo, because it drives an
installed build by bundle id and has no host target: `Audit.swift` runs the audit
and a VoiceOver-order traversal at either text size, `MacDrive.swift` does the
same for the window and answers the sheet question.

## Empty states

Every list in the design is drawn with content in it, so each one had no
appearance when it was empty and rendered as blank space. `EmptyStateView` is
the shared control — an SF Symbol, a headline in `SimpleKanbanFont.serif`, a
line of body copy, and at most one button — with the usual `Metrics.desk` /
`Metrics.sheet` presets. `.desk` is sized to fit a 272pt board column as well as
the 372pt inspector, so there is no third preset.

**Which kind of empty it is decides the way out**, and that distinction is the
whole point of the copy:

| Surface | Headline | Offers |
| --- | --- | --- |
| An empty column | "Nothing in Backlog" | Add a task |
| An empty board | "This board is empty" | Add a task, or a column |
| A board with no columns | "No columns yet" | Add a column |
| No boards at all | "No boards" | New board |
| A search that matched nothing | "No matches" | Clear search |
| The results panel with no matches | "No tasks match “…”" | nothing — the field is right above it |
| An empty saved view | "Nothing due today", one per view | nothing |
| The empty iOS Inbox | "Inbox is clear" | Add a task |
| The macOS inspector with nothing selected | "No task selected" | nothing |

A place with nothing in it offers to fill it; a filter that matched nothing
offers to drop the filter; a saved view offers neither, because there is nowhere
in it to put a card — it is a filter over the board, and a task added to it might
not match it. **A board with no columns is the one place whose offer is not a
card**: there is nowhere to put one, so an "add a task" there would be either
dead or a card filed somewhere the reader is not looking. It offers the first
column instead — composed in the strip on the desk and the iPad, and on the phone
the board's own settings, which is where a phone makes a column. The no-results body names the query back — *Nothing here matches
“drag”* — so the reader sees what was actually searched for rather than what they
meant to type.

**The full-page no-results state is the phone's alone now.** On the desk and the
iPad a query empties nothing, so there is no board left standing empty for it to
explain; what a search that matched nothing looks like there is one line inside
`SearchResultsPanel`, under the field that was typed into — with no Clear button,
because the × is 6pt above it.

The strings live on the factories
(`EmptyStateView.column/.board/.noColumns/.noBoards/.noResults/.savedView/.inbox/.noSelection`)
rather than at the call sites, so the surfaces that show the same emptiness cannot
drift into as many wordings of it — which is not hypothetical: the two "no boards"
states were written independently on the two platforms and had already reached two
symbols, two headlines and two bodies before they were pulled back onto one
factory. All are `String(localized:)`.

Two of them are worth calling out. **The macOS inspector no longer collapses**:
it used to guard on `isInspectorOpen && selectedTask != nil`, so the whole 372pt
panel vanished the moment a card was deselected and the board reflowed under the
pointer, which made the inspector toggle look broken. It now renders at its own
width with a placeholder. And **the iOS empty column does not use
`EmptyStateView.column`** — that copy says "Drag a card here, or start one", and
on a surface showing one column at a time the card to drag is on another screen.
A drag does land there now (see **Drag and drop**), but it is the second way in
rather than the one to name: `PhoneRootView.emptyColumn` says "Add the first task
to this column, or swipe to another" instead.

## What the spec does not define

One faithful gap is left, and it is not an oversight — the design has no
behaviour for it. **There is no sync.** The board is saved locally and the design
defines no remote; the slot the design gave to "Synced just now" reports what the
store last managed to do with the local file instead (see **Persistence**). The
sidebar's other two board rows used to be listed here as well — "Website refresh"
and "Support triage" rendered as designed with hardcoded counts and switched to
nothing. Boards are real now, so that gap is closed rather than described; see
**Boards, columns and the Inbox**.

## Boards, columns and the Inbox

A board is a name, a colour, a code prefix and the columns work moves through:

```swift
struct Board: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var dot: SwatchColor
    var createdAt: Date
    var columns: [BoardColumn]
    var codePrefix: String      // the "NW" in "NW-118" — a label, not a key
}
```

`store.boards` is the sidebar's order and is saved. So is `activeBoardID` — which
board you are on is where your work is, not where you happened to glance, which is
the opposite of the saved view. What the main surface is *showing* is not saved:
`BoardSurface` is `.board`, `.inbox` or `.view(SavedView)`, it is set through
`selectSurface(_:)` (`selectTab(_:)` on the phone), and it belongs to a sitting.

Boards can be created, renamed, recoloured, reordered and deleted from both
surfaces — the macOS sidebar's context menu, its click-to-edit toolbar title and
the Board Settings sheet that menu opens, the iOS drawer's long-press menu and
the same sheet. Renaming, recolouring and deleting are the sheet's on the desk,
and only the sheet's; what the sidebar's menu keeps is the board's place in the
list, which is not a fact about the board. See **Board settings**. Reordering is menu
items rather than a drag on both, because the rows are already card drop targets
and a second meaning for the same gesture would fight the first. A board's dot
is chosen with the same control every other colour in the app is — see **The
colour picker** — and `Board.dots` is now what that control's palette is
*seeded* with rather than the whole of what it offers. Each seed carries its name
— Accent, Stone, Amber, Ember, Pine, Indigo — because a swatch announced as
"Colour 4" tells a VoiceOver user nothing about what picking it does. The last
three are the accent themes' own hexes and take the accent themes' names; the
first is `.accent` itself, the one entry that follows the theme rather than
naming a colour. `Board.dotPalette` is still there as the bare `[SwatchColor]`
the invariants are checked against.

## The colour picker

**One control, one palette, one place the colours live.** A board's dot, a
column's dot and a label's colour are picked with the same `ColorWell` — a
button wearing the colour it has, labelled *Select Colour* — and every one of
them opens the same `ColorPickerPopover` over the same `BoardStore.savedColors`.
That last part is the point: a colour mixed while recolouring a column is
offered the next time a board is recoloured, and one deleted from any picker is
gone from all of them, because there is only ever one list.

It replaced `DotPicker`, a row of six fixed swatches drawn inline by whichever
surface wanted one. Two things were wrong with it. It could offer only what was
written into the source — so "I want this board in *our* blue" had no answer —
and it cost a line of six 44pt targets wherever it appeared, which is why the
add-column composer had to be measured against a landscape keyboard twice. One
button is one target, says what is currently chosen without a ring to read, and
has room behind it for a picker that would never have fitted in a row.

**What the popover holds**, top to bottom: the saved colours as circles, the
current one ringed; a saturation/brightness square with a hue slider beside it;
the hex of whatever is chosen, in a field that is also how it is *typed*; and
Save to Palette beside Done. The spectrum is drawn rather than borrowed —
`ColorPicker` would have opened the system panel on macOS and a full-screen
sheet on iOS, which is a second surface on top of the popover and looks nothing
like the rest of the app.

**What commits, and when.** Pressing a saved swatch is a whole act: it chooses
that colour and closes. The spectrum and the hex field are not — they move a
*draft*, and the draft lands when the picker goes away, unchanged from what it
opened on meaning nothing lands at all. That split is the difference between one
undo step and forty: every colour the picker returns is a store mutation with a
⌘Z of its own, and a drag across the square passes through a hundred colours
nobody chose.

**Deleting is a context menu on the swatch**, not a badge on it: an × inside a
26pt circle sits one slip away from the target that *chooses* the colour. There
is no alert in front of it because nothing wearing the colour changes — a board,
a column and a label each store the colour itself rather than a place in the
list — so what a delete removes is an offer, and ⌘Z puts it back. The accent is
refused outright: it is not a hex but "whatever the accent theme is", nothing
else in the palette can say that, and a board wearing it would be left pointing
at a choice no picker offers.

**A label wears four colours and a picker returns one.** A chip is a tinted
ground with text on it, in light and in dark, and the ten pairs the app shipped
with were hand-tuned — fine for ten, impossible for "any colour the user mixes".
So `LabelTone.pair(from:)` derives all four: the ground is the colour at 13%, so
it sits *on* the card rather than over it, and the text is the same hue taken
away from the ground — darker in light, lighter in dark. The dark ground is
lifted before it is tinted, because a low-opacity wash of a dark colour over a
near-black card is almost the card. The numbers are read off the seeds, which
keep their hand-tuned values: nothing already on a board is repainted by this
arriving. `LabelDef.baseColor` reads the colour back out of the light ground,
which is what puts the ring on the swatch a label was made from.

The palette is board data, in the file beside the labels and the boards, which
cost snapshot **v10**. There is nothing to convert — a v9 file has no palette and
defaults to the six its own pickers were offering — and the bump is for the other
direction, the same argument `Priority.max` made: a v9 build reads a v10 file
perfectly well, silently drops the key, and writes the loss back with every
colour the user had saved in it.

The app **accent** is not in any of this, and there is no accent picker any more:
an accent is a set of related tokens — the accent, its soft wash, the ink that has
to stay readable on it — and picking one arbitrary colour for the first of them
does not answer the other two. All three are parameters of the theme now, and
`SwatchColor.accent` resolves to whichever theme is in force, so a board, a column
or a label wearing *Accent* repaints when the theme changes. See **Themes**.

**Which board a card is on is one control, `BoardDestinationMenu`, and one
convention.** Four surfaces were writing "the Inbox, then every board, with the
current one marked" and marking it three different ways: a tick, a disabled row,
or leaving the current one out of the list. It is a tick, everywhere. The other
two make the menu change shape depending on where the card is — so a board sits
in a different place each time it is opened, and the menu never says where the
card is now — and a disabled row is the one a screen reader skips. Choosing the
ticked destination does nothing rather than re-filing: filing a card onto the
board it is already on sends it to that board's landing column, which is a move
nobody asked for and two of the four menus were quietly making. A surface that
already has a menu of its own — the two card context menus — nests
`BoardDestinationItems` instead of drawing the pill.

**Picking a board from the pill goes to that board.** The pill is only drawn
where a card is already open — the inspector, the phone's sheet — so the card
stays in front of you as it moves, and a card sent somewhere off screen would
leave the panel and the board behind it disagreeing about where it is. The Inbox
is the same journey: it is a panel beside the board rather than a place of its
own, so going there opens it and puts the board back under it. Both are
`BoardStore.showPlace(of:)`, which `reveal` — the deep link, the notification
tap, the Handoff, the Spotlight hit — now goes through as well; an arrival from
outside the app is that plus the two things only it needs, the card selected and
a detail surface opened on it. It is `follows` rather than something `file` and
`unfile` do for everyone: the two card context menus file from the *board*, a
card at a time, and being thrown onto another board after each one is a worse
answer than the card simply leaving. Nor does the ticked destination follow —
nothing moved, so there is nothing to follow — and neither does an archived card,
which lives on the Archive view and is drawn on no board at all.

**On the phone the journey has a second half, and it only ever had one.** The
Inbox there is not a panel beside the board — it is a **modal sheet over it** —
so a card sent *to* the Inbox reads beautifully: the editor drops, the panel
slides up, the editor comes back over it, and you watch the card arrive
somewhere. Going the other way said nothing at all. `showPlace` selected the
board and paged to the card's column exactly as it should, and every one of those
changes happened *behind* a modal still listing the Inbox the card had just left,
with the editor on top of that. The only thing that moved on screen was the
pill's own label.

So the panel takes itself down when the card it has open stops being unfiled, and
the sequence mirrors the one that worked: the editor drops with the panel, the
board is uncovered with the right column already paged to, and the root — whose
own copy of the editor sheet is held back by `isInboxOpen` — puts the editor back
up over it. The rule lives in `PhoneInboxSheet` rather than in `showPlace`
because it is true of a modal and false of a side panel: the iPad's Inbox stands
*beside* the board, so a card filed from there is visible the moment it moves and
closing a panel the user deliberately opened would be taking something away for
nothing. `isInboxOpen` is one flag meaning two shapes and the store cannot tell
them apart; that view is only ever built on the phone.

`UITests/InboxFilingTests` is what can see it, and what it can see is limited in
a way worth writing down: **a sheet makes its presenter inaccessible**, so with
the editor up the panel underneath reports `exists == false` whether it is still
there or has gone — which is the one question being asked. So it is asked in two
halves that only both hold if the panel closed and the editor came back: straight
after the pick the editor is still up with its pill now naming the board, and
then the editor is closed and what is behind it is the board rather than the
list the card has left. The suite files the card home again on the way out, which
is not tidiness — the board file outlives the process, and a suite that eats one
of the three seeded Inbox cards fails `InboxSheetDragTests` and `InboxPanelTests`
for reasons that have nothing to do with either. That return trip pins the
direction that already worked.

**Deleting a board sends its cards — archived ones included — to the Inbox** and
records `.unfiled` on each, rather than deleting them silently. It is one ⌘Z, and
neither surface asks first, matching delete everywhere else here. Deleting the
*last* board is allowed: what is left is the Inbox, which was never one board's,
plus the affordance to make another, so it is a state the user can both reach and
leave. Both surfaces draw `EmptyStateView.noBoards` there rather than a blank
strip, and every surface tolerates `activeBoard == nil`.

**And it survives a relaunch.** `BoardStore.restored` adopts an empty
`snapshot.boards` rather than repairing it: seeding one back would hand somebody
who deliberately emptied their board list a board they did not make, carrying
sample cards that are not theirs. Only the *absence* of a snapshot — a first
launch — seeds. A file damaged past decoding never reaches this path at all;
`BoardFile.load` quarantines it and reports a failure, so "empty" never has to
stand in for "broken".

Counts are real: a board row shows that board's live cards, the Inbox row shows
unfiled ones, and both exclude the archive the same way the header total does.

### The Inbox is global

**There is one Inbox and it belongs to no board.** This is a decided design point
rather than a convenience: a quick capture must never have to pick a board first,
and a per-board Inbox would mean choosing one before you know what you have
caught. It sits above the board list in the source list on
macOS and the iPad, and is a tab on the phone, reachable whichever board is
active — and it is why the board strip no longer opens with an Inbox column; see
**deliberate departures** above.

#### The panel

`BoardSurface` has **two** cases — `.board` and `.view(SavedView)`. The Inbox is
not one of them: it is `store.isInboxOpen`, a toggle like the inspector.

**The switch is a toolbar button, in front of the board's name** — a tray glyph
with the Inbox count beside it, marked when the panel is out the way the
inspector button at the other end of the bar is. It sits before the title because
that is the order the two are in on screen: the panel opens to the left of
everything the bar says. It was a row at the top of the source list until the
Inbox stopped being a destination, and it took that row's drop target with it —
with the panel shut, this button is the only way back by pointer for a card filed
by mistake, because the Inbox is not a column and there is no column to drop it
on. The View menu carries the same switch a third time.

The **Inbox view** in the source list is the other half of the same idea and does
not compete with it: the panel is for moving cards onto the board while looking
at the board, the view is for reading the Inbox with the whole window. Picking the
view hides the panel, because the panel stands beside a board that is no longer
there — and dragging is off on it, as it is on every saved view.

**It is only there beside a board.** `store.showsInboxToggle` is
`surface == .board`, and `isInboxShowing` is that *and* `isInboxOpen` — one
predicate for the button and the panel both, so a button cannot outlive the thing
it opens. On Today there is nothing for it to show, so it is not there to be
clicked.

It is laid out **left of the toolbar**, so it starts at the top of the window
beside the traffic lights and the board's name begins where the panel ends. On
macOS that means the 68pt gap the lights need moves to whichever view is leftmost
— the source list, the panel, or the toolbar itself — and `MacRootView.floor`
grows the window's minimum width by a column when the panel is out, or opening it
would squeeze the board below the width one column needs.

**Getting it to slide out from the right place took two different fixes**, one
per platform, and the same underlying fact: `.transition(.move(edge: .leading))`
offsets a view by its own width from where it sits, and *nothing clips it on the
way*. The panel's travel therefore takes it a column's width to the left of the
board — straight across the source list.

- **macOS** draws the source list **above** the panel (`.zIndex(1)`). They are
  siblings in one `HStack`, so `HStack` order alone put the panel on top: it
  sailed in from the far left of the window over the boards, the saved views and
  the labels. With the list above, the panel emerges from behind it and stops at
  its edge — which is the whole of the effect the animation is meant to have.
- **The iPad** cannot use that: the source list is a `NavigationSplitView`
  column and the panel is in the detail column, so they are in different
  containers and `zIndex` has nothing to say. The detail column `.clipped()`s
  instead, and holds its own leading edge.

Both were caught by copying the repo, slowing the animation to 2.5s, driving the
toggle from a `.task`, and screenshotting mid-flight. At 0.16s a still cannot
land in the middle of it, and neither defect is visible in a static frame.

`isInboxShowing` is `isInboxOpen && surface == .board`, because the panel stands
beside the *board* and a saved view has taken the board's place. It is hidden
rather than switched off, so coming back from Today does not cost a second click:
picking Today was never a decision about the Inbox.

The panel is exactly a column wide (`InboxPanel.Metrics.width` **is**
`BoardColumnView.Metrics.width`, asserted, not copied) and its cards keep a
column's gutter and gap, so a card in the panel sits on the same grid as a card
in the column beside it. It is not a `BoardColumnView` — the Inbox has no name to
rename, no dot and no delete — and its cards drop the column chip the
flat surfaces carry, because inside the Inbox every card is in the Inbox. It
takes drops, like the source-list row: a panel you can see and cannot drop onto
reads as broken.

**The iPad waits rather than overlapping.** The inspector, when there is no room,
draws on top of the board; the panel cannot borrow that trick, because it sits
above the toolbar and an overlay there is the defect `PadRootView` already
documents — the button drawn over and unhittable. So `hasRoomForTheInbox`
hides it until there is room for it *and* a column. That check reads `detailWidth`,
the whole detail column, and not `rowWidth`, which excludes the panel: measuring
the room for a panel off a width the panel is subtracted from is a feedback loop —
it fits, so it appears, so the row shrinks, so it no longer fits. That loop is
what shipped in the first draft, and the panel simply never appeared.

**And it counts the board, not the inspector.** The inspector's width was in that
sum too, and it made the panel decline on an 11" in portrait — 834 less 384 less
320 is 130 — *after* the source list had already closed to make room for it, so
the Inbox button put the list away and did nothing else. Nothing needs reserving
for the inspector here, precisely because the inspector has the answer this panel
has not: it draws over the board. `holdsTheInbox(detail:panel:floor:)` counts what
cannot move.

#### The three panels take turns

Waiting is the right answer to *no room* and the wrong answer to *no room yet*.
**Three** panels compete for an iPad window — the source list and the Inbox on
the left, the task editor on the right — and each is a column wide. What the app
used to do when they would not all fit was refuse to choose: the Inbox was simply
declined, so its button did nothing, which is indistinguishable from a bug; and
the editor drew itself *over* the board, which is the last resort rather than an
answer.

So **whichever panel is opened keeps its room, and the panel furthest from it is
the first to give way**. `PadRootView.yields(to:in:)` is the whole rule: a
`PanelRoom` of what each one is costing the board, walked in the order

| opened | gives way, in order |
| --- | --- |
| source list | the editor, then the Inbox |
| Inbox | the editor, then the source list |
| task editor | the source list, then the Inbox |

and stopping the moment the window holds what is left. Furthest-first is the
reader's own order: attention is where they have just clicked, so the panel at
the other end of the window is the one they are least likely to miss. It is also
why opening either panel on the left collapses the editor *before* it touches the
other one — on an 11" in landscape the two left-hand panels fit together
perfectly well once the editor is away, so making them take turns while a third
column sat on the far side was answering the wrong question.

Four things about how it is wired:

- **Never more than it takes.** Each candidate is only closed while the window
  still does not hold what is open, so a 13" in landscape — which holds all four
  columns at once, and is the shape this layout was drawn for — closes nothing at
  all, and a window that only had to lose the editor keeps both panels on the
  left.
- **A panel that costs nothing is not competing.** A source list the system has
  drawn *over* the board takes nothing from it, so it is not counted and not
  closed. `sidebarCost` is `windowWidth - detailWidth`, which is zero both when
  the list is away and when it is an overlay, and right both times.
- **The ask is the trigger, not the measurement.** The Inbox and the editor are
  watched through their own flags, but the source list is asked for in
  `toggleSidebar` and `revealSidebar` rather than watched taking width — because
  the width it takes is also the *system's* answer. `.automatic` puts the list
  out at launch on an 11" in portrait and takes it away again a moment later, and
  a rule keyed on that collapsed the editor on the way in: traced, `beside=true
  d=516` then `insp=false` then `beside=false d=834`, which is a window that shut
  one of its panels before anybody had touched it. The list's width is therefore
  estimated at the column's ideal on the press that opens it — nothing has been
  laid out yet — and measured whenever it is already out.
- **Zero reads as room.** Before the first layout pass there is no width to
  reason from, and the safe way round is to close nothing.

The rule and `holdsTheInbox` have an invariant between them, and breaking it is
what a dead Inbox button is made of: **whatever closes to make room for the Inbox
has to leave a window the panel will actually draw in**. It did not — an 11" in
portrait with a task selected declined the panel at 834 − 384 − 320, so the Inbox
button put the source list away and did nothing else. `SidebarRoomTests` walks
the iPad widths and every combination of what was open and asserts exactly that,
along with the other half: that whatever closes, what is left holds the rest.

`Tests/PadSurfaceTests` holds the arithmetic and `UITests/PadSidebarsTests`
presses the buttons — **on an 11"**: a 13" in portrait cleared the broken sum by
12pt and passed while the shipped behaviour was broken.

#### Dragging between the panel and the board

Both ways, which is the reason the Inbox is a panel at all: a card caught in the
Inbox goes onto the board without leaving the board, and a card filed by mistake
comes back the same way. The board's columns already took `TaskTransfer` drops;
the panel takes them too, anywhere in it, and its cards are draggable because
they are the same `BoardTaskCard` a column draws.

**The panel's card stack is a column's `ScrollView` + `LazyVStack`, not
`TaskListView`'s `List`.** That is the whole of what had to change, and it is not
a style preference: a `List` handles drags inside its own bounds, so a card
dropped anywhere in the panel except squarely on top of another card never
reached the panel's drop destination behind it. Dragging *out* of the panel
worked the whole time, which is what made it look finished. The swap cost the
panel's rows their `swipeActions` when it was made, and costs nothing at all now
that no card in the app has any.

`isInboxDropTarget` lights the panel, and lives on the store rather than in the
panel because a drop destination nested inside another takes the hover from its
parent — without it the highlight blinked off every time the pointer crossed one
of the panel's own cards. `unfile` refuses a card already in the Inbox: dropping
one back where it came from is a reorder that missed its neighbour, not a move,
and would otherwise cost a ⌘Z and leave "Moved to Inbox" in the history of a card
that never went anywhere.

**`UITests/InboxDragTests` is the only thing that can check any of this.** The
store calls behind a drag are unit-tested and pass whether or not anything on
screen is wired to them; what a drag exercises is the wiring, and which container
gets the gesture first. It is a separate target with a **separate scheme**, so
`-scheme SimpleKanban` still runs exactly the unit suites it always has:

    xcrun simctl uninstall <device> com.n14395.SimpleKanban
    xcodebuild test -scheme SimpleKanbanUITests \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'

The uninstall is the fixture: the board is seeded on first launch and the
simulator keeps it, so a second run measures the board the first run left behind.
That is not hypothetical — it is how these two tests first appeared to fail while
the drags were working perfectly.

**⌘A takes the panel's cards too** when it is out. They are as visible as any card
in a column, and a Select All that skipped them would be lying about what it
selected.

The panel starts shut, which no harness can click open — a simulator takes no
synthetic taps from outside, and driving the host Mac's pointer is a fight with
whoever is using it rather than a verification. So there is a DEBUG launch
argument beside `FirstRun`'s pair:

    xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanShowInbox YES

`-SimpleKanbanHideInspector YES` is its pair, for the same reason: on an iPad in
portrait the inspector is holding the room the panel needs, and a UI test that
wants a column beside the panel has to close it.

**The phone keeps its tab.** It shows one thing at a time and has nowhere to put a
panel, so `PhoneTab.inbox` stays exactly as it was — which is why `visibleTaskIDs`
still asks which tab is up before it asks anything else.

A task is therefore either *unfiled* or *on a board in one of its columns*, and
never half of either. That invariant lives in one type:

```swift
enum TaskPlacement: Hashable, Sendable {
    case inbox
    case column(board: Board.ID, column: BoardColumn.ID)
}
```

One value rather than two nullable fields, because `boardID` / `columnID` has
exactly two legal shapes and the others — "on a board, in no column", "in a column
on no board" — are bugs that surface only as a card nobody can find. There is no
way to spell them here. `TaskItem.placement` is the only writer of the two stored
fields, `performMove` is the only thing that sets `placement`, and `file(_:onto:)`,
`file(_:onto:column:)`, `unfile(_:)` and `move(_:to:)` are the only ways in. Every
set of tasks the store adopts is put back through `TaskPlacement` at init, where
**the column is the fact that decides**: column ids are unique across boards, so a
card naming a column lands on whichever board owns it whether it arrived claiming
that board, another, or none, and a card naming no column — or one no board has —
is unfiled.

**A task can be moved between boards, and back to the Inbox, from both surfaces.**
On macOS, drag a card onto a board row in the sidebar to file it there and onto the
Inbox row to unfile it, or use the inspector's board menu and its "Move to"
segments. On iOS, the detail sheet's board row does the same. On both, the card's
own context menu carries **Move Board ▸** and **Move Column ▸**. The board menu — the row above the segments, on both
surfaces — is the route back: it lists the Inbox first, and the phone's card drag
reaches the board's own columns and nothing else — there is no Inbox panel on
that surface to drop onto — so without it filing a card would be a one-way door.

### Codes

`code` — "NW-118" — is the human-facing label a task carries. It is minted
from the **destination's** `codePrefix` plus one global `nextSerial`, and unfiled
tasks take the constant prefix `"IN"`. One counter for the whole file rather than
one per board: the prefix is what tells two boards' codes apart, and a per-board
counter would hand two boards the same number and make the prefix load-bearing.

**It is not drawn in the editor, and it never was on the card.** It led the
header of both task panels — the desk's inspector and the phone's sheet — until
it was taken out of them: it is the one thing on that panel nothing can be done
with, it names nothing the user chose, and it cost the first line above the title
on the surface where the title is the point. Where it *does* show is everywhere
the app has to name a card outside itself — the `simplekanban://` link Copy Link
puts on the pasteboard, the plain-text half of a drag, the due-date reminder,
Spotlight, the Markdown export, and macOS's quick-add confirmation — plus the
Trash row, where two cards with the same title have to be told apart. The search
field still finds a card by its code, which is what makes one worth reading out
loud in the first place. `UITests/EditorHeaderTests` opens the editor on both
idioms and looks for the label that used to be there.

**A code never changes once minted.** Filing an IN-141 onto Northwind leaves it
called IN-141, because by then it may be sitting in someone's commit message. That
is also why the migration renumbers nothing. A board given no prefix derives one
from its initials, upper-cased and capped at four characters, and falls back to
`"NW"` — a board that cannot mint a code is a board no task can be added to.

### Columns, and the last one

Columns are a **board's** data, not a fixed set and not the store's: they live on
`Board.columns`, they are written with the board, and they can be added, renamed,
recoloured, reordered and deleted. `BoardStore.columns` is the active board's,
which is what the macOS strip and the iOS pager draw.

**A new board starts with its Done column and nothing else.** It used to arrive
holding a copy of the seed workflow under fresh ids, so that a card could go on it
straight away, and the first thing anyone making a board of their own did was
delete four columns they had not asked for. Then it arrived with none at all,
which left the one column every board is *required* to have as something the app
added behind the user's back along with their first real one.

One column, and it is the one that cannot be argued with. Every surface that
draws a board with no **working** column offers the column composer where it
would otherwise offer a card — `workingColumns.isEmpty`, not `columns.isEmpty`,
which now answers "no" for a board with its whole workflow still to say. Two
things follow from that and are worth stating: `landingColumn` is `nil` on such a
board, so a card dropped on it is refused rather than landed in Done and
completed on arrival; and `detachSurfacesFromMissingColumns` points the phone's
pager at the first *working* column, so `mobileAddPlacement` answers with the
Inbox exactly as it did when a new board had no columns at all.

**Making one opens its settings.** The sidebar's row used to become a text field
where it stood, and the phone put up an alert, on the argument that a board *is*
a name. It is not: it is a name and the columns work moves through, so the next
thing to do after naming one is always to say what its columns are. Both routes
now make the board under `Board.defaultName` and raise `BoardSettingsView` on it,
with the name field focused and **empty** —
`BoardSettingsRequest.namesNewBoard` — so the first keystroke names it and the
`+ Add column` button is already on screen above the Done column. Closing without
typing leaves the board called "New Board": `renameBoard` refuses an empty name,
and `commitRename` reads the kept one back.

Two things had to hold for that to be safe. The first is that **deletion's
invariant is untouched**: `deleteColumn` still refuses to take a board's Done
column or its last working one. A board is allowed never to have had a column and
is not allowed to be emptied down to none; from the outside those read as one
rule, and underneath they are not, because the second has cards in it to lose. The second is `mobileAddPlacement`. `mobileColumnID` is session state that
outlives a board switch, and a board with no first column leaves it naming the
*previous* board's — which `placement(forColumn:)` resolves happily, since it
looks an id up across every board, and `isPlaceable` then agrees. A card added on
a blank board would have landed on the board before it, invisibly. It goes to the
Inbox instead.

The **Inbox is not one of them** — it is global; see above.

**The Done column is the board's last one, and every board has one.** Arriving
in it ticks off a task's outstanding sub-tasks, tints its due chip green, and is
what the weekly meter and "Archive completed" mean by shipped. `Board.doneColumn`
is where that is written down, once; everything asks the store rather than the
task — `store.isDone(task)`, `store.isDone(column:)`, `store.column(for: task)`.

The column menus say so before they are pressed: **Move Left** and **Move Right**
are both greyed on the Done column, and **Move Right** is greyed on the column in
front of it, on the desk's header menu and the phone's chip menu alike. A menu
item that can be pressed and does nothing is indistinguishable from a bug, and
there is nothing to explain afterwards that the position does not already say —
`ColumnChipMenuTests` presses both cases.

It is not deletable and not re-orderable, which is what makes reading it off the
position safe: `addColumn` inserts **in front of** it, `moveColumn` refuses to
lift it and clamps anything sent past it, `deleteColumn` refuses it outright, and
the settings sheet offers neither its row as a grip nor its arrows live. It is an ordinary column in
every other way — renameable and recolourable, because real boards call it
Shipped, Live and Published, and `SeedData.contentCalendar` already ships one
called Published. A board that has no columns yet gains its Done column along
with the first column its owner adds, so there is never a board holding nothing
but somewhere to finish. A board arriving from an import with a *single* column
has no Done column at all: that column is where the work is, and reading it as
Done would have every card on the board arrive complete.

**Up to v8 this was a `ColumnRole` stored per column** — `backlog`, `active` or
`done` — and the Done column was the first one whose role said so. Two of the
three roles never did anything; nothing in the app ever branched on `backlog` or
`active`, and the picker offering them was a choice with no consequence that
could not be corrected afterwards, because there was no `setColumnRole`. The
third allowed a board to hold *two* Done columns where only the first counted, a
distinction invisible everywhere in the app except the warning that had to be put
in front of a reorder. `migrate(v8:legacyDoneColumns:)` moves whichever column v8
would have sent a tick to to the end of its board, and nothing else about the
board changes — no card moves, no column is lost. A stored `doneColumnID` was the
alternative and would have needed a fallback for the case where it named a column
that had gone; the only sensible fallback is "the last one", so the id would have
existed purely to allow Done in the middle of a board.

**Column management exists on every surface**, because a board made on the phone
would otherwise be stuck with its four starting columns for good — and because
the desk's version of it was scattered across three controls that only exist
while the board is on screen. It is one view now, `BoardSettingsView`; see
**Board settings** below. macOS keeps its column header menu and editor popover
(`BoardColumnView.columnMenu`, `BoardColumnEditor`) and the trailing
`AddColumnTile` as the fast paths they are. **The composer holds everything the
column's own editor does** — a name, an abbreviation and a dot — because it is
that editor a moment earlier. It used to take a name alone, leaving the other two
reachable only by making the column and then opening the row that had just
appeared. The abbreviation matters because `MoveToPicker` draws it, and on the
phone that control is the only route a card has off a column.

Left empty, Short falls back to the whole name (`addColumn`, and
`aColumnWithNoShortNameBorrowsItsName`), so the field costs nothing to ignore.
The placeholder is the word "Short" rather than an echo of the name saying so:
measured, "Code Review" in the desk's 96pt field renders as "Code Reviev", and a
control that looks broken while explaining itself has explained nothing. Return
in the composer's Name moves to Short rather than making the column — a Return
that stepped over a filled-in field directly under the caret is the wrong
promise, and the keyboard says **next** there and **done** in Short.

The swatches open on **`BoardColumn.defaultDot`, which is deliberately not one of
the six**: it is what a column made without touching them has always been, so
nothing is ringed until somebody picks, and an untouched composer makes exactly
the column it made before. It is a name rather than a literal because
`BoardStore.addColumn` takes it as a parameter default and the sheet opens its
picker on it, and two spellings of one default differ the day one is changed. The
pick is held in the view until Add Column is pressed — there is no column to
recolour before then — which is the one join `aColumnKeepsTheColourItWasMadeWith`
cannot see, so it was measured through the accessibility API instead: pick Indigo,
add, reopen the row, and Indigo is the ringed swatch. `addColumn` and `moveColumn` are defined over the
**active** board — a column carries no board id, only the board that holds it —
so the sheet calls `selectBoard` on appear rather than risk adding board A's
column while showing board B. `rename`, `recolor` and `delete` find the board
from the column and are safe anywhere.

### Work-in-progress limits

A column may carry a **WIP limit** — `BoardColumn.limit`, an optional `Int`,
`nil` on every column until somebody sets one. The count pill in the column
header then reads `4/3` instead of `4`, and takes a colour: the theme's *warm*
due-chip recipe at the limit, its *hot* one over it. Both phone orientations
draw the same pair through `ColumnPill`, and the column widget draws it from the
digest, so a column that is over its limit says so everywhere it is counted.

**It is advisory, and that is a promise rather than an omission.** Nothing in
the app refuses a card because of this number: not a drag, not a drop, not the
composer, not a paste of forty lines, not a move from Shortcuts, not a tick that
sends a card to a full Done column. Refusing a drop would punish the exact
moment somebody is trying to reorganise a full column, which is the moment a
full column most needs it — and a limit that blocks work is a limit people turn
off. `ColumnLimitTests/nothingIsRefusedByALimit` asks every one of those
entry points, so the promise is a test rather than an intention; enforcing a
limit later would mean deleting that test on purpose.

**The count is what the board draws, not `cardCount(inColumn:)`.** That one
counts archived cards, deliberately and correctly — it exists for the
delete-a-column warning, where a promise to move four cards must not then move
nine. A limit built on it would climb for as long as the board was used: every
card ever finished and filed away would still be pressing against the limit, and
a column would sit permanently over one with nothing on screen to explain it.
Archived is off the board, and off the board is not work in progress. So
`BoardStore.load(ofColumn:)` reads `visibleTasks(in:)` — the same array the
header already has, and the same number the pill has always shown. There is no
"but what about while filtering": the board is not drawn from the search query
(see **It is a search, not a filter**) and a saved view draws no columns at all,
so the pill's count and the limit's count are never two different numbers.

**Set with a toggle and a stepper**, in board settings and in the popover off a
column header — the same pair `SavedViewEditor` uses for a view's card cap,
because that is the app's one other optional number and two spellings of it
would be two controls to learn. Switching it on starts at what the column
already holds: any fixed default would put most columns straight over a limit
nobody had chosen, which is a warning colour arriving as the result of turning
the feature on. Zero clears rather than meaning "nothing may be here", and the
range is 1–99 — not a rule about kanban, but a field that accepts `999999999` is
a pill eight points wide drawing `4/999999999`.

The colours are the due chips' own recipes rather than two new theme
parameters. "Getting tight" and "past it" are precisely what warm and hot
already mean everywhere else, all twenty presets have tuned them against their
own ground, and a `ThemeWip` pair would have made a column setting a *theme*
schema change.

### Board settings

**A board is one thing, and this is where it is edited**: its name, its colour,
and the columns it is made of — each one's name, abbreviation, colour and place,
plus the two that change the board's shape, adding a column and throwing one
away. `BoardSettingsView` is a sheet on all three surfaces, raised through
`BoardStore.boardSettings` — a `BoardSettingsRequest` naming the board, the
column to arrive unfolded on, and whether to land the caret in the name field.
The root presents it, once, because most of what raises it is a menu and a menu
can set a flag but cannot present a sheet: the same split the Trash makes.

It was the phone's alone. On the desk the same capabilities existed as three
controls in three places — a rename in the sidebar's context menu, a colour in a
popover off it, a column's four fields in a popover hanging off a column header —
with the order of the columns spelled as *Move Left* / *Move Right*, one column
at a time, and nothing on screen showing the order being changed. The first two
are gone; the column popover stays as the shortcut it is.

**Rename Board, Board Colour and Trash Board left the sidebar's menu the way
*Rename board* left the phone's ⋯ menu**, and for the reason given there: an item
for something the first item's destination already holds is a second door to one
room. The sidebar row's rename field and the swatch popover hanging off the row
went with them — nothing else opened either — and so did
`BoardSidebar.Metrics.dots`. What the menu keeps is Board Settings and **Move
Up** / **Move Down**: where a board sits among the others is a fact about the
list, and there is nothing in a board's own settings for it to be a field of.

A board is still renamed in one click where its name is actually on screen — the
toolbar title is editable in place, which the sheet does not replace, because a
name being edited under the pointer that is pointing at it is not a destination.
Deleting deliberately kept no such path. It is the one act on this menu that
takes the board out from under the pointer, and the sheet's button carries the
sentence a menu item cannot: *Its cards move to the Inbox rather than being
deleted.* The phone drawer's own long-press menu still carries **Trash Board**
beside Board Settings…, which is the drawer's call to make, not this one's.

**Two of the things it does reach past the board's own chrome, and both ask
first.** Everything else in the sheet is visible the moment it happens and is one
⌘Z from being back.

- **Trashing a column moves other people's cards.** The alert says how many and
  where to — `cardCount(inColumn:)` and `refuge(ifTrashing:)`, the second being
  the same first-column-left `deleteColumn` moves them to, so the warning and the
  mutation cannot name different places. The count includes *archived* cards,
  because the move does. And it says the last true thing: the column itself goes
  to the Trash and can be restored for thirty days.
**A reorder used to ask as well, and no longer can need to.** What made a column
the one a tick sent a card to was its role rather than its position, so a board
with two Done columns changed where every future tick landed the moment they were
dragged past each other — invisibly, with no undo step announcing it. Done is the
last column now and does not move, so `doneColumnID(afterMoving:toOffset:)`, the
alert and `ColumnMoveWarning` are all gone. `BoardSettingsTests` asserts the
absence: no reorder from anywhere to anywhere changes where completed work lands,
adding a column leaves it where it is, and the Done column refuses every move.

`BoardSettingsTests` also pins the numbers — the refuge is where the cards
actually land, the count includes archived cards, an empty column's warning
mentions no cards — and `UITests/BoardSettingsSheetTests` presses the button on
both idioms, because every one of those numbers would go on being right with the
alert deleted and the button wired straight through.

**The board's add-column tile is gone.** It was a column-wide dashed pill for a
while — 272pt of board, a whole card's worth, spent for ever on two words — then
a 38pt strip with the label turned to read bottom to top, and now nothing: a
board's columns are set up once and edited rarely, and a permanent control on the
board for it cost 38pt of every board for ever. Adding a column is `+ Add column`
in this sheet, reachable from any column header's ⋯ menu and from the sidebar's
board menu.

The one thing on the board that still offers one is the **empty state**, because
a board with no columns has no column header to reach the sheet through. Its
button raises this sheet with the composer already open —
`BoardSettingsRequest.addsColumn`, the same bargain `focusesName` makes for the
routes that say *rename*: a button that promises a column should land in a field,
not in a sheet with a button in it. `BoardSettingsTests` asserts the strip no
longer draws a tile and that the empty state still opens the composer.

`VerticalText` went with the tile — it existed to turn that one label and nothing
else asks for a sideways run of text. It is in the history if it is ever wanted:
a `Layout` rather than the obvious measurement-into-`@State`, because
`rotationEffect` is a *draw* and leaves the claimed size alone.

**The composer sits between the working columns and Done**, which is where the
column it makes will appear: `addColumn` inserts in front of Done, and Done stays
last. On the end of the list it read as "add a column after Done", which is the
one place a column cannot go.

**The rows re-order by dragging**, and the Move Up / Move Down pair in the open
editor stays beside it rather than being replaced by it. A drag is not a control:
it cannot be reached by keyboard, VoiceOver cannot offer it, and Switch Control
cannot perform it — and the pair is the only route while a row is open, which is
exactly when somebody is deciding where the column they are editing belongs. The
grip is the *closed* row only: an open row is one being typed into, and a drag
starting on its fields would fight the caret.

**A dragged column is marked by the gap it will land in, not by a row it will
not.** The rows used to be whole drop targets that tinted themselves, which was
wrong twice over: the row that lit up was not where the column was going —
`dropColumn(_:onto:)` resolved a row into a gap by the direction of travel, so
aiming at In Progress from above landed the column *after* it — and the top of
the list could not be named at all, there being no row above the first one to aim
at. So the list took the mark the board's cards and the checklist's rows already
use: two half-height insertion targets over each row, `.above` and `.below`, and
a 3pt accent capsule drawn on the edge the drop would land against. The zones
reach 6pt past each row so one row's halves meet the next one's in the middle of
the 2pt gap, and they are in the tree **only while a column is in the air** —
plain hit-testable views over a row nobody is dragging onto would take the tap
that opens it.

Which is why the sheet has to know a column is airborne at all. The signal is the
payload closure `.draggable` evaluates when the *session* starts — the same one
`BoardTaskCard.lifted()` uses — deferred into a task of its own, because writing
state straight from there is writing it during a view update. It carries
`BoardStore.liftExpiry` with it: a column let go over nothing ends its session
without telling anybody, and zones left over every row would eat every tap until
the sheet was closed. The Done row draws a single zone rather than two: nothing
lands after it, so the whole of it means *in front of Done*.

No caret is drawn against the row in the air, nor in the two gaps that column
already sits between — a mark promising a move that `dropColumn` will refuse is
worse than no mark.

**The row for the Done column draws neither a move nor a trash**, and says why in
a line of text where they would have been, rather than as three disabled buttons
somebody has to press to find out. Its name, abbreviation and colour are editable
like any other column's.

Deleting a column moves its cards — archived ones included — to the first column
left, and each of them records the move, so a card changing column is explicable
from its own history. A delete of the board's Done column, or one that would
leave it with no working column, is **refused with a `ColumnRefusal` the surface
can show** rather than ignored: from the outside, "delete" doing nothing is
indistinguishable from a bug.

## Themes

**Everything the app looks like is one value.** `Theme` carries the two faces,
the window's ground, the panel wash, the card, the ink, the wash, the highlight,
the two status hues and the two chip recipes; `Palette` holds one and every
colour, font and corner in the app is a question put to it. Switching theme is an
assignment — there is no registry to keep in step, nothing to invalidate and
nothing to tell.

Twenty ship with the app, transcribed from the theme explorer. `ThemePresets.all`
keeps them in **the document's own order**, which is not the order they were
designed in: round two (`2a`–`2j`) is the first section of that page and round one
(`1a`–`1j`) the second, so **Ember is the eleventh of the twenty**. The ids are the
document's references, kept so that a conversation about "1e" and a tile in the
picker are the same thing. Ember is the reference point — the shipping theme,
tuned, with the flat charcoal opened out into a slow warm gradient and the accent
taken a little hotter — so it is the one to read against the app to see what a
parameter does.

### Two slots, not one theme

Every preset is absolutely light or absolutely dark. Ember has no light values
behind it and Porcelain has no dark ones, so a single active theme would mean
either abandoning the system's light/dark switch or inventing values no designer
wrote. The board keeps **one theme of each kind** and the appearance setting picks
between them, the same arrangement macOS uses for wallpaper:

```
Settings ▸ General ▸ Appearance
  Appearance   System | Light | Dark     ← which of the two is showing
  Themes …     Porcelain in light, Ember in dark
```

`ThemeSettings` holds `lightID`, `darkID` and the user's own themes, and
`select(_:)` puts a theme in the slot its own `appearance` names and nowhere
else — so a dark theme cannot end up in the light slot and leave the app
unreadable at noon. `theme(for:)` falls back to the preset rather than failing,
twice over: a slot may name a theme this machine has never seen (a board file
copied from one that had a custom theme), and a theme may have been edited into
the other kind since the slot was set.

Defaults are **Ember** dark and **Porcelain** light. There is no light twin of
Ember among the twenty; Porcelain is the document's own light control — warm
whites, ink text, one vermilion accent — and is the quietest thing to wake up to.

### The parameters, and where each one lands

The sections in the editor are the document's, in its order and under its names,
so that somebody with the explorer open in one window and the editor in the other
does not have to translate.

| Parameter | What it paints |
| --- | --- |
| display font | Board titles and the inspector's task title. Nothing else — a display face used for a fourth thing stops marking the other three. Family, weight and slant. |
| ui font | Everything else. Its weight is a **baseline**: the app's two hundred call sites shift with it, so 400 leaves them exactly where they were written and 500 lifts the whole interface by one step. |
| window bg | `palette.windowFill`, a `LinearGradient` behind the whole window. Nineteen of the twenty carry a gradient. |
| panel overlay | The sidebar and the inspector, *translucent over the gradient* — so the ground runs through them rather than stopping at their edge. |
| card | Fill, hairline and radius. The radius is the one size the design varies from theme to theme. |
| ink | The text colour and its two quieter tiers. |
| wash | The search field, count pills, the segmented track, an empty meter, and any due date further out than soon. |
| highlight | The accent, its soft tint, and what can be read on top of it. |
| status hues | Done, and this-week/medium. |
| label chips | The **recipe**, not the colours — see below. |
| due chips | Overdue/today and soon. Anything further out takes the wash; a finished task takes the done hue. |

Three of those needed a decision rather than a transcription.

**Label chips are a rule.** The document fixes four chips per theme — `HEALTH` is
one teal in every dark theme and another in every light one — but a label here is
not one of four fixed things: you make labels and give each one a colour from the
same picker a board and a column are coloured from. So `ThemeChipRule` carries the
three numbers that turn *any* colour into a ground and a text (lift, ground
strength, text shade) and the document's four pairs fall out as examples of it.
`palette.chipTone(for:)` applies it at render time, which means every chip already
on the board re-tints when the theme changes, including the ones made before it
did. Dark themes lift the colour before tinting because a 19% wash of `#1F6F63`
over a near-black card is very nearly the card.

**There is no third status hue.** The overdue red is the due chip's own, and
`priorityColor(.max)` takes it at full strength, so the app's one alarm colour is
said once rather than twice.

**On-accent is a parameter rather than a rule.** Ultraviolet's gold takes
near-black and Aurora's mint takes a deep green, and neither is something the app
could have worked out.

### What a theme cannot do

The contrast floor. `ThemeInk.muted` and `ThemeInk.faint` are used exactly as
written for the things that are *not* text — a hairline, a dot, an empty meter
track — but anything that has to be **read** goes through `palette.inkText(_:)`
and is never drawn below 68% ink. Text that cannot be read is not a style choice,
and a theme that could set it could produce an app nobody can use. The editor says
so under the two fields.

The scrim is not the panel overlay either. A scrim is the *absence* of what is
behind it, so it goes through `shadow(_:)` and stays black in a dark theme — see
**Accent** below for what happened the one time those two were the same colour.

### The browser and the editor

`ThemeBrowserView` shows the themes as **small pictures of the app** rather than
rows of swatches: a theme is a ground, two faces, a card and eight colours working
together, and six circles say almost nothing about how that comes out.
`ThemePreviewTile` is that picture, and every parameter is somewhere in it — the
gradient at its real angle, the panel strip over it, the title in the display face
at its own weight and slant, the card at its own radius inside its own border, a
label chip through the rule, a due chip, a priority dot, the wash.

**The two buttons at the top do two jobs.** Each names the theme in its slot, and
pressing one filters the grid to the half that can fill it — eleven dark themes or
nine light ones. Naming matters because only one of the two is ever on screen:
somebody setting their dark theme in daylight sees nothing happen to the app, and
the lit button saying *Dark · Rainforest* is the only report they get. Filtering
matters because twenty pictures in one scroll is a lot of scrolling to compare two
dark grounds nine tiles apart — and the two halves are never alternatives, since a
light theme and a dark one are both in use at once. The browser opens on whichever
half is in force, which is the one you came to change.

Pressing a tile puts it in its slot, which under the filter is simply the slot
named on the lit button. **New Theme** follows the filter too — one item rather
than a light one and a dark one, because a menu that could make a theme the grid
would then hide is a menu that does nothing visible — and an import switches the
filter to whatever kind arrived.

**On the desk it is a window of its own**, opened from Settings ▸ General ▸
Themes… and declared as a `Window` scene beside About. A sheet was wrong for it in
three ways: it is pinned to the width of the pane it hangs off, it cannot be
resized, and it blocks the window it is attached to — and this is a surface for
*comparing* pictures while the theme it chooses repaints the board behind it. The
grid is adaptive rather than fixed, so a wider window is more columns: three at the
900×720 it opens at, five at 1400, one at the 372pt floor. The phone keeps a
sheet, having no windows to open, and keeps a Done button for the same reason —
a window has a close box and a second door to the same room is clutter.

`ThemeEditorView` exposes every parameter as a typed value, not a slider: the
difference between a theme and a near-miss of one is a number you can read back.
The colour control is the app's own `ColorWell` over the same
`BoardStore.savedColors`, so a colour mixed while building a theme is offered the
next time a label is coloured, and the other way round. Opacity is a field beside
it rather than a fourth pair of hex digits, because two of a theme's colours are
only meaningful as tints and the document states them as `rgba(...)` with the
alpha written out.

**A preset opens as a copy.** `ThemeSettings.save(_:)` refuses one outright: a
reference point that can be overwritten is not one. A new theme starts from the
preset for its slot rather than from black, because a form of thirty empty fields
is not a starting point.

Deleting a custom theme **asks first**, which deleting a saved colour does not.
The difference is that there is no ⌘Z on a settings surface and a theme is an
evening's work, where a deleted colour removes an *offer* and nothing wearing it
changes.

### The file

`ThemeDocument` writes plain `.json`, pretty-printed with sorted keys, colours as
`#RRGGBB` or `#RRGGBBAA`. It is about sixty lines and is meant to be read: a theme
should be something you can paste into a message, put in a gist, or open in an
editor and change one hex in. Giving it a bespoke extension would buy an icon and
cost all of that.

One shape is written — an envelope with a format marker, a version and an array,
so exporting one theme and exporting a library are the same format — and three are
read: that envelope, a bare array, and a bare object. The last two are what
somebody who wrote a theme by hand is likely to hand it, and refusing them would
be pedantry. A file that will not read names the field that broke, because
`DecodingError`'s own description names a Swift type and a coding path and neither
means anything to somebody editing a hex.

An import always gets a **fresh id**. Two people who both started from Ember and
edited it would otherwise be carrying the same id on two different themes, and
importing one would silently overwrite the other.

### Where they live

In the board file, at snapshot **v12**, exactly where the accent was and for the
same reason: a theme somebody spent an evening on is their work, and work belongs
in the file that gets exported, backed up and synced rather than in a preference
that stays behind on the old machine. Which of the two slots is *showing* is not
in there — that follows the system appearance and the `AppAppearance` override,
both of which belong to the machine.

`adoptContent` does not take them, along with the active board. **Importing a
board must not repaint the app**: a board exported from a Neon Grid install would
otherwise turn a Porcelain one black on the way in. Themes travel by their own
door.

Selecting, saving and deleting register **no undo step**, along with `selectBoard`.
How the app looks is a preference rather than board data, it is not in
`BoardMutation`, and a ⌘Z aimed at a card the user had just moved should not
repaint the window.

`migrate(v11:accent:)` is the step, and it is the only one that needs the raw
bytes: v12 removes `accentTheme`, so the field is gone from the decoded value by
the time the step runs, and `BoardSnapshot.legacyAccent(in:)` reads it out of the
JSON the way `legacyDoneColumns(in:)` already does. **The old accent is not thrown
away.** Ember's rust is the default themes' own accent already, near enough, so it
migrates untouched; Pine and Indigo exist nowhere in the twenty, so rather than
silently repaint an app that has been green for a year the step seeds a copy of
each default wearing the old colour and selects them — with `onAccent` recomputed
by luminance, because white text on Pine's green is not the same decision as white
text on Ember's rust. Ink migrates to the presets: it meant "the accent is the
text colour", which is a thing a theme has no parameter for.

### The seventeen faces

The presets call for seventeen families, and all seventeen are bundled under the
SIL Open Font License with their licence files beside them — about 5.6 MB, because
fifteen of them ship as **variable** fonts: one file with a weight axis rather
than five files. Five static weights of seventeen families would be eighty-five
files.

That is also why `FontCatalog` exists. SwiftUI's `Font.custom` takes a PostScript
name, not a family and a weight, and the names CoreText fabricates for the named
instances of a variable font are not names anybody would guess: Work Sans at 800
is `WorkSansRoman-ExtraBold`, Space Grotesk at 700 is `SpaceGrotesk-Light_Bold`,
DM Sans at 500 is `DMSans-9ptRegular_Medium`. So the family and the weight go to
the font matcher and the name that comes back is cached, keyed on all three of
family, weight and slant. A family the matcher has never heard of returns `nil`
and is cached as `nil`, so a theme naming a font nobody has does not re-run the
matcher on every frame.

A theme may also name any font **installed on the machine** — it is the user's
theme, and if they have bought a face they should be able to set the app in it.
Those come second in the picker and under their own heading, because a theme built
on one will not travel: opened anywhere else it falls back to a system face, and
the editor says so under the row when that is what has been chosen.

Only Instrument Serif and Newsreader ship a real italic, which is all the presets
need. A slant asked for on any other family is **sheared** rather than dropped —
worse than a drawn italic and much better than a theme that asks for italic Sora
and silently gets roman.


## The app icon

The icon is the design document's `2e` **capped columns** mark: three columns at
x = 20, 41 and 62 of a 100-unit box, each led by a short header rule with cards
stacked under it — **2, 3 and 1**, because a board is not a staircase, it is work
piled unevenly across the middle of it. Nine rectangles and a gradient. That is
the whole drawing, and it is written once, in `AppIconArtwork`.

What varies between one icon and the next is exactly three things, which is what
`AppIconArt` carries: **the ground**, **the colour of the three header rules**,
and **the colour of the six cards**. The ground is a `ThemeGradient` rather than
a gradient type of its own, because the theme-matched icons *are* a theme's
window gradient and a second type would be the same value written twice.

Settings ▸ **General** ▸ *Appearance* carries an **App icon…** row under
*Themes…*, naming whichever icon is being worn, and it opens `AppIconPickerView`
— the icon large at the top, the ten grounds under it, and one switch.

### Ten grounds, and twenty more from the themes

The ten are the document's fourth round, `4a` through `4j`: three stops at nought,
a half and one, eight running corner to corner and two — `4i` and `4j` — straight
down. The mark is one colour in all ten, which is what that round settled: the
ground carries the depth, so a second tone in the mark would be a third idea on
an icon that has two. `4f`, peach through rose to violet, is the one the app has
always shipped wearing and so the one the picker starts on.

**Icon follows app theme** replaces that choice with the document's fifth round —
a theme's own icon, by its rule rather than by transcribing its twenty outputs:

> the theme's window gradient becomes the ground, its highlight colour the header
> caps, its ink the cards.

Twenty lines of transcribed hexadecimals would have been twenty chances to drift
from the presets they were copied out of. `AppIcon.art(matching:)` is the rule
itself, so the twenty cannot disagree with `ThemePresets` — and a theme built in
the editor this morning gets a matching icon for nothing.

The switch resolves against the theme in the slot **the appearance is showing**,
so a Mac set to follow the system wears the light theme's icon by day and the
dark one's by night.

### The two platforms mean different things by "set the icon"

**macOS draws it.** `NSApplication.applicationIconImage` takes a picture at run
time, so `AppIconInstaller` renders `AppIconMark` through `ImageRenderer` at the
Dock's own grid — the artwork in 824 of a 1024 canvas, the rest being where the
shadow goes — and hands it over. Every icon works there, including one matching a
theme that exists only on this machine.

What it cannot do is change the icon **in Finder**, or in a Dock the app is not
running in. That is the bundle's own `.icns`, and this app is sandboxed and does
not rewrite its own bundle. The picker says so under the icon rather than leaving
somebody to quit, see the old icon in Finder, and call it broken.

**iOS names it.** `setAlternateIconName(_:)` takes the name of an icon already
compiled into the app, so the alternates are baked: `Tools/make-app-icons` writes
thirty `.appiconset`s — the built-in one plus nine grounds (`4f` *is* the built-in
one) and twenty theme-matched — and
`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS[sdk=iphone*]` compiles them in.
macOS is excluded from that: with no alternate-icon API there, they would be
twenty-nine `.icns` files nothing can ever ask for.

The alternates carry the **classic per-idiom sizes** rather than one 1024. An
alternate is never shown in the App Store and never drawn above the Home Screen's
own size, so the 1024 would be most of a megabyte of nothing each; measured, all
twenty-nine together come to about 2.3 MB, against 20 MB the other way.

The one thing that falls off the end: **a theme the user made has no icon in the
bundle**, so on iOS *Icon follows app theme* wears the one the app shipped with
until that theme is one of the twenty. The desk has no such limit.

### The generator is not a second copy of the drawing

`Tools/make-app-icon.swift` compiles the app's own theme sources — that is what
`Tools/make-app-icons` is for — and reads `AppIcon.catalogue`, so every number in
the bundle comes from the same place the picker draws from. A hexadecimal
transcribed into the tool is a hexadecimal that can disagree with the tile, and
the whole promise of a picker is that the tile is what you get.

Two checks hold that together. Regenerating reproduces the shipping
`AppIcon.appiconset` **byte for byte**, so the refactor that made the tool
general is provably not a change to the icon; and `AppIconTests` renders
`AppIconMark` through `ImageRenderer` and samples it, so the `Canvas` in the
picker and the Core Graphics in the tool — which share numbers but not a line of
drawing code — are held to the same corners.


## Editing

Both detail surfaces — the macOS inspector and the iOS sheet — write straight
through to `BoardStore`, so an edit lands on the board card as it is typed.

- **Title and description** are text fields. The title is single-line: Return
  commits it and hands focus back, and a paste has its newlines and runs of
  spaces folded to single spaces on the way in, because a card has room for a
  line and not for a paragraph. The description keeps its vertical axis — it is
  meant to hold paragraphs — so iOS gives it a Done key in the keyboard bar. A
  title emptied to nothing is restored on blur rather than leaving an
  unreachable card; a task that has genuinely never been named renders as
  "Untitled".
- **Priority** is a menu whose label is the design's existing dot-plus-name.
  Four of them — Max, High, Medium and Low — listed **least urgent first**, so
  the menu reads Low, Medium, High, Max upwards. That is `Priority.leastFirst`
  rather than `allCases`, and it is the one surface that runs against the
  board's own order: a picker on a card is a scale being read off, and a scale
  reads upwards, where the Set Priority submenu is a command aimed at a
  selection and wants the loudest thing at the top. Named on the type rather
  than reversed in a view body, so which order a surface draws is something a
  test can hold — and it means the menu opens on the case a card starts at. **Max is the only
  one that does not take the accent** — it is the red the overdue chip already
  uses, this app's one alarm colour, because High *is* the accent and a fifth
  tone of it would not read as louder. A card starts at **Low**
  (`Priority.default`), which is also the one priority the Markdown export leaves
  unsaid: everything arrives at the floor, so a mark on a card means somebody
  decided something rather than that a card exists.
- **Due date** is the design's chip, made tappable: Today / Tomorrow / Next week
  shortcuts, a calendar, and Clear. The calendar is ``MonthGrid``, drawn here
  rather than taken from the system — see **The calendar is hand-drawn**.
- **Sub-tasks and labels** are edited in place; see below.
- **Escape** clears a draft in all three of the fields the design defines it
  for — the column composer, the sub-task draft and the label picker — and
  cancels a rename in the label manager. Where there is nothing to clear it is
  passed on rather than swallowed, so it still closes whatever is presenting the
  field.

**The two attribute cards are the controls, not boxes around them.** Due and
Priority sit side by side in an `AttributeCard` — a name over a value, each
taking half the row — and the card is drawn *inside* the button's or the menu's
label rather than around it (`View.inAttributeCard(_:)`, handed an
`AttributeCardStyle` by whichever surface is drawing). So the name, the padding
and the empty half of the card open the calendar or drop the priority menu
exactly as the chip in the middle of it does. Before, only the value itself was
live: a card the size of a thumb answered a press on about a fifth of itself,
and on a pointer the cursor changed over a word and nowhere else. The hit shape
is stated to the card's own corner radius, and each control keeps its
`accessibilityLabel` — otherwise VoiceOver read the card's name and then the
control's, "Priority, Priority".

### The calendar is hand-drawn

`DatePicker(.graphical)` on macOS is a **fixed size**, and the popover it sits in
is not. Measured through the accessibility tree: 138×148pt inside a 248pt column,
whatever it is proposed. `.frame(maxWidth: .infinity)` only centres it — the
calendar moved from x=1328 to x=1383 and stayed 138 wide — and neither
`.controlSize(.large)` nor a larger `.font` moves it a point. Both were tried and
measured before the grid was written; a stranded calendar with 19pt cells and
half the panel empty beside it is what that control gives you.

So the month is drawn here. `MonthGrid` lays out to whatever width it is given —
seven columns of `maxWidth: .infinity` — which makes a day cell **35pt on the
desk and 45 under a finger**, against the system's 19. Three things come with
that beyond the size: it reads in this app's type and palette rather than the
system's; the same calendar is now drawn on both platforms, where before macOS
and iOS each got whatever their own graphical picker happened to be; and the
arithmetic is testable, which a system control's never was.

**Six weeks, always.** A month that needs five rows still draws six, so the panel
does not change height as the arrows are pressed and a row does not move out from
under a pointer already on its way to it. The neighbouring months fill the edges,
greyed, and they are live: a date at the start of next month is one press away in
the row it actually falls in, and picking one takes the grid with it.

The month on screen belongs to the **panel**, not the task — paging forward to
look at next month must not move the due date, and the two part company the
moment an arrow is pressed. It is set when the panel opens, to the card's own
month or to this one when the card has no date yet. `DueDateField.month(_:by:)`
does the stepping in whole months from the *first*, because the 31st is not a day
of every month and a step that resolved it forward would land on the 1st of the
month after and skip one every time it was pressed from a long month.

`MonthGridTests` is the arithmetic: six whole weeks for every month of a year and
for both kinds of February, every row starting on the calendar's own first
weekday, the month itself present once and in order, the edges consecutive with
it, a month that starts on the first column having no spill above it, the year
rolling at both ends, and the stepping — including twelve steps being a year, out
and back. It runs against a fixed Gregorian calendar and `en_GB`, so a suite run
in another region does not report a different month.

**A field that opens has to open with the keyboard in it.** Every inline field
in this app is opened *by* something — the column's "+", the sidebar's New board,
the board's name in the title bar, Add column, the label popover, ⌃⌘N — and none
of them offers a second click to recover with, so a field that does not take
focus is the whole interaction failing silently: a placeholder, no caret, and the
first thing typed going wherever the keyboard actually was.

`@FocusState` set from `onAppear` does exactly that. The assignment lands before
AppKit has finished installing the field and is dropped with nothing reported.
Three of the app's fields shipped like it, and what made three possible is that
each spelled the idiom out for itself. There is one spelling now —
`View.focusWhenReady(_:)` — and one `Task.yield()` inside it, which puts the
assignment on the far side of the run-loop turn the view was created in. The
alternatives were measured against the built app and do not work: `onAppear` does
not, a bare `task` does not (it starts in the same turn), and `defaultFocus` does
not either outside the popover it was reached for in `LabelEditor`, because it
settles a scope's default when the scope is *established* and these fields appear
inside one that already exists. A sleep long enough to work — 50ms was — is the
same yield written as a number that happens to be right on one machine.

`@AccessibilityFocusState` is a different focus, moves the VoiceOver cursor, has
no such problem, and `PhoneNavDrawer` still sets one from `onAppear` on purpose.
`FieldFocusTests` tells the two apart by how the property is declared rather than
by an exception list, and asserts both halves: nothing writes a `@FocusState`
from `onAppear`, and the set of fields going through the modifier is the set
named in the test — so a new field cannot quietly be added with the old line.

**The add-column composer asks for a name and nothing else**, which since v9 is
everything there is to say about a column when it is made: there is no role to
choose, and the new column lands in front of the board's Done column, which stays
last. `BoardSettingsTests` asserts that no surface has grown a picker back.

The board used to carry a composer of its own, in the dashed tile at the end of
the strip, and it closed again when the keyboard left it — a button that becomes
a field leaves a control sitting where a button should be, on every board, for
the rest of the session. Both the tile and that trade have gone with it; the
sheet's composer is a row in a list and closes with the sheet.

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

### Completing, reopening and deleting

A task reaches Done three ways: dragged there, sent there from the **Move
Column** menu, or completed where it stands — a circular checkbox on either card,
a context-menu item on both platforms, and the tick in the detail panel. The
"Move to" segments are not one of them; see **Boards, columns and the Inbox**.
The checkbox is `CompletionToggle`, which
is also what the checklist rows are drawn from: same accent fill, same border,
same tick glyph, so the board and the checklist cannot drift into two ideas of
what "done" looks like. Only the corner radius is a metric, because a card wants
the circle the spec draws beside a title and a row wants the design's rounded
square. On a card the control sits *over* the button rather than inside its
label: a button nested in another button's label never sees the click, and
ticking a card must not also open its detail surface. `reopen` sends a completed
task back to the newest column its own history names that is not the Done one,
and to the board's landing column when it has none, so the Done tick is a
round trip rather than a one-way door. Neither verb applies to a filed card: `complete` and `reopen`
refuse an archived task outright, where Restore is the only verb — see
**Saved views and the archive**.

**The detail surfaces carry a tick**, and it is another door onto
`toggleCompletion` rather than a second verb: pressing it moves the card to its
board's Done column, which is the rightmost column on every board the app seeds,
and pressing it again reopens the card. A tick a finger cannot take back is a
trap.

**Where it sits is not the same on all three surfaces**, because the row it can
join is not:

| surface | where | drawn from |
| --- | --- | --- |
| macOS, iPad | `TaskInspector.header`, with the trash and the close ✕ | `CompletionToggle.deskHeader` / `.sheetHeader` |
| phone | `PhoneDetailSheet.titleRow`, level with the title | `CompletionToggle.sheetPanel` |

On the desk and the iPad the panel's header is one row of three verbs — finish
the card, throw it away, put the panel down — and **all three claim the same
square**: `TaskInspector.Metrics.headerButton`, 32pt on the desk and 48pt on the
iPad, with one `headerGlyph` size inside it. The tick brings its own button, so
its `hitSize` is the only place that agreement can be *stated* rather than
happening to hold, which is what `TouchTargetTests` asks. It was beside the title
before, where it was the only control in a column of fields — a state verb in the
middle of an editing surface, sized against a 26pt serif line rather than against
anything it shared a row with.

The phone keeps its tick beside the title because its header has the ✕ and
nothing else: the trash is a row at the foot of the sheet, so there is no set of
verbs up there to join, and a lone tick beside a lone ✕ is not that row. It stays
`.top`-aligned there for the reason it always was — a centred row puts the circle
halfway down a title that wrapped, which is beside no line at all, and the 44pt
touch square is exactly twice the 13pt radius either way, so the circle lands on
the title's *first* line without a nudge and the alignment survives two lines.

**Disabled rather than hidden** where there is nothing to complete into, which a
board arriving from a hand-edited file with no Done column can be. A control that
vanishes on one card and not the next reads as a bug rather than as a board
missing a column. On an archived card it *is* absent, because there the verb is
Restore and only Restore — see **Saved views and the archive**.

The panel's tick is drawn whatever **Tick cards off from the board** says, and
that is the point of it: with the card's own circle switched off, this and the
context menu are what is left. See **What a card shows**.

**`BoardStore.toggleCompletion(_:)` is still the one act**, because the board
card, the panel and the sheet had each spelled out `isDone ? reopen : complete`
for themselves, and three copies of a two-line rule is two chances for one
surface to answer differently from the one beside it. `canToggleCompletion(_:)`
is the matching question, and the detail panels' tick is what asks it: the two
directions have different conditions — reopening needs only that the card is in
Done, so on a completed card `canComplete` is *false* while the toggle is still
live, and completing needs a Done column to complete into, which a hand-edited
board can be without. `BoardStoreMutationTests` holds all four cases.

**The verb is Trash, and it happens immediately.** It is a context-menu item and
an inspector button on macOS, and the long-press menu plus a row at the foot of
the sheet on iOS. It had a trailing swipe on the flat surfaces until the swipes
went; the menu carried the same verb the whole time, because a swipe is
unreachable with VoiceOver or Switch Control. Trashing a task takes
its drafts, its open editing sessions and its search memo with it, and the
selection falls to the next card in the same column — else the one above it —
rather than jumping the board. A one-line field that an open session had emptied
is put back *before* the undo step opens, so undo is never the one path that
lands an untitled card on the board. There is still no confirmation, and now
there are two things behind it rather than one: ⌘Z, and thirty days in the trash.
See **The trash**.

**Every column ends with the offer to add to it.** `ColumnAddRow` — the dashed
"+ Add task to <column>" row — was the phone's alone, drawn under the last card
of a column page where a thumb already is. The desk and the iPad had nothing
there: the only way to add to a column was the `+` in its heading, and a column
is taller than the window as often as not, so on one scrolled to the bottom that
control was off screen and the offer with it. `BoardColumnView` now draws the
same row, from the same view and the same numbers — 13.5 bold at 45% ink, 14 of
padding, a 1.5pt dash on a 16pt corner — because the three are meant to be one
row and a preset per platform is how two of them drift.

**The composer opens at the end that asked for it, except where a keyboard
would take that end.** This is the one thing that could not simply be copied:
the phone has no inline composer at all, it opens the card's sheet. On the board
the heading's `+` opens the draft at the head, where it has always been, and the
foot's row opens it under itself — `BoardColumnView.composesAtFoot`, local state
because it is which control was used, not anything about the board. A card is
appended (`BoardStore.mintTask`), so the foot is also where the card is about to
appear. There is one draft per column — `addingPlacement` is a single placement
— so the two ends cannot both be open, and pressing the foot's row while the
head's field is up moves the field rather than opening a second one. The row is
drawn under a column that has cards and no draft: an empty column already
carries the same offer in its empty state, and the composer *is* the offer
taken.

**On the iPad the foot's row opens the draft at the head**, and
`Metrics.composesUnderTheAddRow` is the whole of that difference — `false` on
the pad preset, `true` on the desk's, rather than an `#if os()` in a shared body
(C1). The reason is the software keyboard: a field at the foot of a column is a
field at the foot of the screen, and the column is a scroller nested inside the
board's own, so the keyboard's inset does not reach it and nothing scrolls the
field clear of the keys. It opened *under* the keyboard — a button that read as
having done nothing, with a focused field somewhere off the bottom of the
screen. The head of a column is above every keyboard there is.

**And a committed card is brought into view, wherever the field was.** The card
is appended, so a draft taken at the head of a long column lands off the bottom
of it: `commitDraft()` returns the id it made and `BoardTaskComposer` raises
`BoardReveal.intoView` on it. `intoView` is the smallest ask in that vocabulary
— nothing happens at all when the card is whole on screen already, which is the
common case — and it is the same request a click makes, so the column and the
strip answer it the way they answer everything else. The Inbox panel's composer
draws without a relay and asks for nothing; a card in the Inbox is in no column
to be scrolled to.

Every `+` that opens an editor rather than a one-line composer — the iOS
quick-capture button, and the source list's capture popover on the desk —
creates its card untitled and opens the editor with the title field focused, so
closing it again without filling anything in would leave an untitled card
behind. It does not: the dismissal takes the card away again, by the ×, by the
drag-down, or by clicking away from the popover, all of which land on
`BoardStore.discardIfBlank`.

**What it asks is what the editor was closed with, not whether anything was ever
typed in it** — which is the way round this used to have it. It tracked *touch*:
any mutation at all disqualified a card for good, so a capture whose priority was
tried and put back, or whose title was typed and deleted, or which merely started
with a due date because of Settings ▸ **New tasks**, stayed on the board as an
untitled card nobody asked for. Now the card is kept beside a copy of itself *as
capture made it*, and the dismissal compares the two —
`TaskItem.hasSameContent(as:)`, which is the fields the controls write and
nothing else, the code and the timestamps and the activity feed being the card's
record rather than anything filled into it.

Comparing against what was made rather than against a row of empty values is the
only honest way to ask, because two of those controls do not start empty: a new
card carries `Preferences.defaultDueDate` and the placement the `+` was pressed
in, so "no due date, in the Inbox" is the empty state on one machine and a card
somebody filled in on another. It also makes the editor's own board menu count —
a capture filed onto a board with nothing else in it is a card the user meant.
And it is asked exactly once: whatever the card is when the editor closes, it is
one the user kept, and opening and closing it again never takes it away.

The iOS **flat** list is a real `List` rather than the `LazyVStack` it started
as. It was made one purely for `swipeActions` — a hand-rolled swipe has to fight
the scroll view for the gesture, re-implement the full-swipe threshold, and is
invisible to VoiceOver — and **that reason expired when the cards stopped
swiping**. It is kept there rather than re-chosen: the two containers are not
interchangeable, and on Search, a saved view and the Archive the difference does
not arise, because none of those is a place a card can be dropped. The rows are
stripped back to clear backgrounds, no separators and the design's 10pt gap, so
the cards look exactly as they did.

**The two surfaces that *are* places use the other container**, and that is the
difference spelled out: a `List` handles drags inside its own bounds, which is
why `InboxPanel` and the board's columns are stacks, and a board page or an Inbox
that stayed a `List` took no drop anywhere on it. `PhoneCardStack` is that stack,
drawn by `PhoneColumnPage` and `PhoneInboxSheet` — see **Drag and drop**.

### The trash

**Throwing something away is a thirty-day promise, not a deletion.** The three
containers-and-cards the user can get rid of — a task, a column, a board — all
say **Trash** now rather than Delete, and what they remove goes into
`BoardSnapshot.trash` as a `TrashedItem`: what it was, and enough about where it
was to put it back. `TrashView` lists them with a countdown, a Restore and a
Delete; after thirty days they go on their own.

**Where it is reached from, and why it is not Settings.** It was a tab of
Settings, and it was on the wrong shelf: every other subject in there is a
preference about how the app behaves, and this is the user's own work sitting out
a thirty-day countdown. A preference can wait; a card thrown away on Tuesday
cannot wait past the thirtieth day, and getting it back should not be three taps
into a preferences sheet. So it has three doors, all raising the one flag,
`BoardStore.isShowingTrash`:

- **macOS and iPad** — a **Trash** row in the source list, under **Manage**,
  below the labels, with the Trash itself in a popover beside it. It was a bin at
  the foot of the list — a glyph in the corner, the shape the Finder, Mail and
  Photos all give it — on the reasoning that the rows above are places the board's
  work *is* and this is where work goes when it stops being work. It moved into
  the list under **Views** first, beside the Archive, on the reading that work
  leaves the board two ways and both of them should be rows. The Archive earns
  that section and the Trash does not: an archived card is still a card the
  filters above could match, while the Trash holds columns and whole boards as
  well and nothing in it is on the board at all. So it sits with the app's own
  furniture, and the heading over that furniture is **Manage** rather than Labels
  because it is no longer one row about one thing. The count is the row's pill, where the Archive's is, and
  the glyph fills while there is something in there — the one thing the bin said
  that a count does not. The row is built beside the popover rather than by
  `viewRow`, because the Trash cannot be a `SavedView`: those are predicates over
  the board's cards, and this holds columns and whole boards too. The popover is
  told to hang off the trailing edge on the desk and left to place itself on the
  iPad, where `.trailing` put it over the source list and hard against the left
  edge of the screen — the same split `BoardColumnView`'s column editor makes.
- **iPhone** — the board menu at the top right, which is that surface's drawer for
  everything with no other home. It reads "Trash (4)" while there is something in
  it: a menu row has nowhere to put a trailing count, and "Trash" alone makes
  opening it the only way to learn there is nothing in it. The sheet is presented
  by `PhoneRootView` rather than by the header, because a menu can raise a flag
  and not a sheet — the same split `SettingsSheet` makes for the drawer's Settings
  row, and the reason the flag is on the store rather than in a view.

`Tests/TrashSurfaceTests` reads the source for both halves — that `SettingsView`
builds no `TrashView` any more, and that each surface has a door — and
`UITests/TrashSurfaceTests` presses the phone's and checks the Trash is what comes
up. Neither throws anything away first: what the list holds depends on what the
user has deleted, and a fixture that has to be empty is one the suite running
before it can break.

This sits *beside* ⌘Z rather than replacing it, because the two answer different
questions. Undo answers "I did not mean that", and answers it better — it puts
the board back exactly, cards and all. It is also gone when the app is quit, and
it walks backwards, so a board deleted three edits ago costs the three edits as
well. The trash answers "I meant it at the time and I do not any more", which
nothing here used to answer at all.

**The three kinds are not the same shape, and the trash does not pretend they
are.** A task is the whole card and comes back whole, into the placement it
carried. A column and a board are *containers*, and deleting either has never
taken its cards with it — a column's cards move to the first column left, a
board's go to the global Inbox, each saying so in its own history. Trashing
changes none of that: what is kept is the container, and restoring one brings
back the container. The cards were never in danger and are not waiting in the
trash for anybody. Positions are carried rather than looked up on the way out, so
a restored board lands where it sat rather than at the end of the sidebar, and
they are clamped on the way back in because a list changes shape in thirty days.

**Restore has exactly one refusal**, and it is not the one you would guess. A
card whose board or column has since gone is *not* refused — it lands in the
Inbox, which is where every other card that cannot find its column lands; holding
a card hostage to a container it never belonged to would be the wrong side of the
trade. A **column** whose board has gone is refused, because a column is nothing
but a place on a board and inventing one to hold it would be inventing a board.
The alert says so and names the way past: restore the board first. A refusal
mutates nothing and so registers no ⌘Z.

**Delete is the guarded button, which is the reverse of the rest of the app.**
Everywhere else the act happens and undo is the net; here there is no net, so
Delete asks first and names what it is about to destroy. It is the only
confirmation in the app that is not about throwing away the entire board.

**A card says what went.** `BoardToast` floats a line along the bottom of the
board reading "Moved *X* to the trash" and takes itself away after three and a
half seconds. It is the app's one strip for saying what it has just done, and a
sync the user asked for ends there too — see **Pull to sync**. Trashing has no confirmation and never had one, so until this the
only sign that a board had gone was that it was no longer there — fine for a card
clicked in a column, thin for a board deleted out of a menu, and the only place
in the app where something sizeable could leave without the screen saying so. It
also teaches the trash exists, which is otherwise a thing you have to notice a row
in the source list to find out.

It is a **message rather than a control**: no Undo button, because ⌘Z is the undo
and is on the Edit menu naming the exact step, and a button that is there for
three seconds and then is not is a worse promise than a keystroke that is always
there. It is not hit-testable, so it can never take a click meant for the card
still under it. A selection of four gets **one** card counting them rather than
four replacing each other too quickly to read; a refusal gets none, because
nothing happened. `Announcement` carries an `id` so that trashing two cards
with the same title in a row reads as two announcements — keyed on the text
alone, the second would look like no change and inherit the first's dismissal
timer. It is session state: not in `BoardSnapshot`, not in `BoardMutation`, and
cleared by `apply`, so a ⌘Z takes the sentence away with the act it describes.
For VoiceOver it is an `AccessibilityNotification.Announcement` rather than an
element in the tree — a thing that appears for three seconds and then is not
there is worse to meet than one that was never there.

**Trashing, restoring and emptying are all ordinary board mutations**, which is
why `trash` is in `BoardMutation`. Without it a ⌘Z after a trash would put the
card back on the board *and* leave the copy sitting in the trash — one card,
twice. The sweep is the exception: dropping what the thirty days have run out on
is the promise being kept rather than anything the user did, so it registers no
step, and a ⌘Z that could reach into a bin the app has already emptied would be
undoing the passage of time. It happens on the way in (`restored(file:sync:)`)
and when the surface is looked at; in between, `trashedItems` *filters* by age
rather than sweeping, because reading a list must not write to the file.

**The trash is local to the device.** It rides in `board.json`, which is written
on every save whether CloudKit is on or not, but it has no record type in the
sync schema — so `restored(file:sync:)` reads the file for it even on the path
where the records won. "What is on my board" and "what did I throw away here" are
not the same question, and a trash arriving from another Mac would offer to
restore a card this one has never seen. What crosses devices is the board: a card
trashed on one simply leaves the board on both. An **import** does not adopt the
arriving file's trash either, for the obvious reason, and neither does a
**backup restore** — for the less obvious one, that taking a backup's trash would
resurrect the things the user has permanently deleted since, which is the one act
in the app that is meant to stick.

### Sub-tasks

Every row edits in place — the box toggles, and the text is a `TextField` driven
by the same `beginEditing`/`endEditing` session as the task title, so a row
retyped a letter at a time is one activity entry and one ⌘Z. Delete is an `×`
revealed on hover on macOS and the row's context menu on iOS, which is also the
path VoiceOver has on both: a control that waits for a pointer is a control a
screen reader cannot ask for. Reordering is a drag on the row itself and logs
nothing — the order is on screen, and a feed of "sub-task moved" would bury the
changes that matter. Every row is 44pt tall on touch and the whole of it takes
focus, the dashed `+` box on the add row included — a `TextField` is only live
across the text it draws, so the row rather than the field is what a finger
aims at; see **Touch targets**.

### Labels

`renameLabel`, `recolorLabel` and `deleteLabel` finish the vocabulary. A rename
never regenerates the `key`: the key is what every task stores, so re-slugging it
from the new name would leave every task carrying the old one and silently
detach the label from all of them. Deleting a label strips the key from every
task that had it and records the removal on each, because a chip disappearing
from a card should be explicable from that card's own history. A new label's
name is capped at 40 characters and a chip truncates to one line — past that it
is all ellipsis and no information, and one long label takes a whole row of the
flow layout to itself.

`LabelManagerView` is the board-wide surface: every label with an inline rename,
`LabelDef.tones` as a swatch row, a count of the tasks carrying it, and delete.
It is presented as a sheet from the macOS sidebar and the iOS drawer, and
kept a plain view so a Settings pane can host the same body later. The rename
field takes focus from anywhere on its 44pt name line and announces itself as
"Label name" — a placeholder is not read once a field holds text, and this one
always does. An *applied*
chip carries its own remove control as well — an `×` revealed on hover on macOS,
a long-press menu on both — while a chip on a card, which is a read-out and not
a control, renders exactly as it always has.

Those tones carry their names — Indigo, Violet, Pine, Red, Amber, Stone — beside
their hexes on the model, the way `Board.dots` does and for the same reason: a
swatch announced as "Colour 4" gives a VoiceOver user its position and nothing
about what choosing it does, and a name kept in the picker instead drifts from
the colour the moment either is edited. Naming one of the app's two swatch rows
and not the other would only have moved the problem. `LabelDef.palette` is still
there as the derived pair list `recolorLabel` and the round-robin in `addLabel`
take, exactly as `Board.dotPalette` is.

### Activity

The feed is live rather than static text. Moves, renames, description changes,
priority and due-date changes, label add/remove, and sub-tasks added, renamed
and removed all append an entry, newest first, and timestamps age ("just now",
"20 min ago", "2 hr ago", "3 days ago"). The sub-tasks a move into Done ticks
off arrive as one counted entry rather than one line each.

An entry stores *what happened* — an `ActivityEntry.Kind` case plus whatever its
sentence needs — and the sentence is rendered at display time, so history written
under one language reads correctly under another. `moved`, `labelAdded` and
`labelRemoved` carry the column or label *name* beside its key: an entry is a
historical record and must still read correctly once the thing it names has been
renamed or has gone. Entries from a build that wrote finished English survive as
`.legacy` and are shown verbatim — re-deriving them would be a guess.

Text fields log **once per editing session**, not once per keystroke:
`beginEditing` snapshots the value on focus and `endEditing` compares on blur.
A session is keyed by (surface, task, field, sub-task), so the macOS inspector
and the iOS sheet editing the same title cannot share — and corrupt — one
before-value, two checklist rows on one task are two sessions, and pointing a
surface at another card closes the session against the card that was actually
being edited. The due-date popover's whole lifetime is one session: trying three
dates in the calendar before settling on a fourth writes one entry, not four.
Naming a task that was created untitled is not logged as a rename — "Created"
already says it.

The feed itself is `Sources/Shared/ActivityFeed.swift`, drawn the same way on
both surfaces: a dot at 22% ink, the sentence at 60%, the relative stamp at 35%,
with `Metrics.desk` and `Metrics.sheet` for the geometry. The macOS rendering is
the reference — the iOS sheet had no activity section at all, so the same task
showed its history on one platform and hid it on the other.

Stamps age without a relaunch. The feed reads `dayClock.today` once, so
everything re-renders at midnight when "today" becomes "yesterday", and each row
sits in its own `TimelineView(.periodic(from: .now, by: 60))` for the sub-day
text — per row rather than per feed, so a tick invalidates one line instead of
the panel. The timeline wraps the row's whole concatenated `Text` rather than the
stamp alone, because the stamp has to flow and wrap inline after the sentence and
only one `Text` does that. The feed draws **rows only, no heading**: both surfaces
label their own section at their own size.

## Undo

⌘Z is the system's, not a stack of this app's own: `RootView` hands the window's
`UndoManager` to the store, and every board mutation registers a step against it.
Going through the platform's manager is what buys the standard macOS Edit menu
reading "Undo Trash Task" and "Redo Move Task" — the action names are
`String(localized:)` — and iOS shake-to-undo, for nothing. `canUndo`/`canRedo`
are exposed for the menu-bar items Phase E adds. With no manager in the
environment every mutation still works and ⌘Z simply does nothing, which is what
a preview and a test see unless the test asks for one.

A step is a **snapshot, not an inverse**. `undoable(_:_:)` captures the board's
value state — `tasks`, `labels`, `nextSerial`, `boards`, `trash` — before and after the body and
registers only if the two differ, so a drop that changed nothing stays off the
Edit menu. An inverse hand-written per mutation is where undo bugs live, and the
board is arrays of value types, so holding one costs a retain rather than a copy.
Nested calls collapse into the outer step, so a mutation assembled out of other
mutations still costs exactly one ⌘Z. Adding a task and discarding an untouched
quick capture are each their own step: they cancel out on the board but not on
the stack, and an unregistered removal sitting on top of the capture's step is
exactly the shape that lets a later ⌘Z put the discarded card back.

Because a snapshot step reverses *everything* the board did since its
before-state, one rule holds throughout:

> Every board mutation registers its own undo step immediately. Editing sessions
> coalesce *activity entries*, not undo steps — with one exception: continuous
> text, where a session groups the keystrokes it owns and nothing else.

So a title typed a letter at a time is one ⌘Z, while four dates tried in the
calendar are four ⌘Z and one activity line. "Nothing else" is kept true at every
step boundary — a registration or a restore — by moving each open session's
before-state up to the board as it then stands. Without that, a description
field that keeps focus while the pickers and the checklist are used in the same
panel eventually files one step that reaches back past all of them, or puts back
something the user had already undone.

The move cannot be made on its own, because the text typed since the last
boundary would then belong to no step at all: the step above it was snapshotted
before that text existed, and the session's own step now starts after it.
**Every keystroke belongs to exactly one step**, so at a boundary the unfiled
text is dealt with first.

- At a **registration** it is filed as a step of its own, from the *oldest* open
  session — only the oldest covers the whole unfiled delta, and filing a younger
  one would orphan the older prefix again. It goes in underneath, so the first
  ⌘Z takes back the thing that interrupted the typing and the second takes back
  the typing. The undo group is closed and reopened around it, or the two share
  the run loop's group and one ⌘Z reverts text typed before the user clicked
  anything.
- At a **restore** it cannot be filed at all: a registration made while the
  manager is undoing lands on the *redo* stack. So it is carried across the
  restore instead — a ⌘Z aimed at an older step leaves what is still being typed
  on the board, and the session goes on owning it and files it on blur. Text the
  restored board sets itself is not carried (undoing the session's own earlier
  step is asking for that step's value), and carried text is stripped out of the
  redo snapshot, or the same keystrokes sit on both sides of a step where no ⌘Z
  can reach them.

**The selection is deliberately not restored.** There are two of them
(`selection`, a set, and `sheetID`), they belong to a surface rather than to the
board, and neither is in `BoardSnapshot`; a restore only drops the ids that have
stopped naming anything. The cost is known: undoing a delete brings the card
back while the inspector stays on its neighbour, and fixing that belongs to
whatever offers the undo rather than to the board. The accent theme is not on
the stack either — it is a preference, not board data.

## Search

Search is multi-token AND rather than a phrase match, so "drag columns" finds a
title with the two words apart. Each token is matched against a task's title,
description, code and label keys, and both sides are folded case- and
diacritic-insensitively — "cafe" finds "Café". The folded text is memoised per
task so a keystroke re-runs the search without re-folding it. The memo is
stamped with a monotonic per-task counter rather than `updatedAt`: `Date.now` is
coarser than the gap between two consecutive mutations, so two edits can land on
the same instant and a memo keyed on it would go on serving the first one's text.

An archived task is in no search. It has left the board, so it is not something
the search failed to find — the Archive view is where it is looked for.

### It is a search, not a filter

**Typing does not touch the board.** It used to, on the desk and the iPad: the
columns were drawn from the query's answer, so a keystroke took cards off the
board and the reader was left with a board that had silently lost most of itself.
Worse, it could not answer the question people actually type into a search field
— *where is that card* — because the card is usually on **another board**, and a
filter over the board you are already looking at is the one shape of answer that
can never say so.

So the field opens ``SearchResultsPanel``: a list of every task in the app, from
every board and the Inbox, best match first. A row is three lines — the **title**,
the **first line of the description**, and then **board, column, priority**, with
the due chip beside the title. The description is what tells two cards with
similar titles apart, and the first line is where people put the sentence that
does it; the last line is a funnel, which board, then which column of it, and only
then what the card is like. **No labels**: they were on that line for one build
and came straight out — a card carries any number of them, they are the widest
thing the line can be asked to hold, and none of them tells one result from
another. Choosing one goes there — `BoardStore.reveal(_:)`, which is the same
call a `simplekanban://` link makes: the card's board (or the Inbox panel), the
card selected, its detail open, and the query cleared behind it.

`BoardStore.searchResults` is the list, and it is the *only* thing the query
feeds. Nothing else narrows: `visibleTasks(in:)`, `inboxTasks` and
`tasks(in:today:)` all ignore it. `SearchScopingTests.nothingOnTheBoardIsNarrowedByAQuery`
is that rule as one assertion.

Two things follow that are worth naming because they used to be the other way
round. **A card stays draggable while a query is running** — `allowsCardDrag` no
longer asks about the query, because the rows on screen are still the board's own
order. And **⌘A still takes the whole board**, for the same reason.

### Ways out of a search

The panel is an overlay the header draws rather than a popover, so nothing
dismisses it on the app's behalf. There are five ways out, and for a while the
obvious one was missing: **Escape**, **choosing a result**, the **×**, putting
the **folded row** away — and **clicking anywhere else**, which is what a reader
who has finished with the list actually does. Without it, somebody who typed,
read the list and went back to the board was left with the list over the top of
it.

That last one is a catcher — a clear layer under the panel, starting where the
header stops, so every control in the bar, and the field itself wherever the fold
has put it, still takes the click it was given. It is deliberately not "the field
lost focus": clicking a *result* takes focus out of the field before the row's own
click lands, so a panel that closed on focus would be a panel whose rows cannot be
clicked, and on the iPad a tap outside a field takes nothing away from it anyway.
The click that dismisses is **swallowed**, the way a popover swallows the click
that closes it — the card under the pointer is one press away rather than selected
by a press that was meant to put a list down.

The source list is the one place the catcher cannot cover: on the desk it is drawn
*above* the header, because the Inbox panel has to slide out from behind it, and
on the iPad it is a column of the split view. What a click there does is change
the surface, so that is what is watched instead, and the search ends with it.

**The query survives the click.** It ends the reading of the list rather than the
search: what was typed is still in the field with its × beside it, so the caret
goes back and the reader carries on. Escape is the explicit cancel and takes the
query with it. The one thing that does go is a folded row with nothing typed in
it, which exists in order to be typed in.

`UITests/SearchResultsTests` is the half only a running app can answer, and it is
the *pair* that matters: a query typed, a panel of matches over the board, and
the board still holding the cards that did not match — plus choosing a result and
landing on the card with the field empty behind it, and a tap on the board putting
the panel down while leaving the query where it was. It runs on the iPad because
that is the platform a UI test can drive; the desk's half was measured through
the accessibility API while this was written, which is the only way to drive that
one — the accessibility tree pressed the rows and read the geometry back, the
same technique the board's reveal was measured with.

### Best match first

An empty query is every task, in board order: the panel opens on the whole of
what there is and narrows as the reader types. Once there is a query, every token
still has to match — that is unchanged — and what is new is that a hit is
*scored* by where it landed. ``TaskSearch`` is the whole of it, and the ladder is
short on purpose: each step is a distinction a reader would make out loud, and a
finer grading is a number nobody can predict from the screen.

| the token is | worth | example |
| --- | --- | --- |
| the whole title | 10 | "Sync" for `Sync` |
| the start of the title | 7 | "sync" for `Sync engine v2` |
| the start of a word in the title | 5 | "columns" for `Drag-and-drop between columns` |
| anywhere else in the title | 3 | "co" inside `macOS` |
| in the note, code or a label | 1 | "reconnect" in a description |
| nowhere | — | the task is not a result at all |

A hyphen starts a word, so "drop" is a word of `Drag-and-drop` rather than
something buried in it. The score is the sum over tokens, so two words of a title
beat one word of a title and one word of a note. Ties break on `updatedAt` — of
two cards that answer equally well, the one the reader was last working on is the
one they meant — and then on board order, so the sort is stable.

### Where the query still applies

There is one `query`, bound by the macOS toolbar, the iPad toolbar and the iOS
search field alike. The panel is the answer on the two pointer platforms. The
phone is the one surface where a query still narrows something in place, and the
rule there is unchanged: **it never narrows a surface that is not showing a way
to clear it.**

- **macOS and iPad** — the field opens the results panel and nothing on screen
  is narrowed, so there is nothing to announce and no "Filtered" indicator to
  show. Both fields carry an `xmark.circle.fill` clear button while non-empty;
  Escape closes the panel and clears the query, which is what a search field does
  everywhere else on the desk.
- **iOS Search tab** — the field is on screen and the flat list *is* the results
  list, drawn full-screen instead of in a panel. Same `searchResults`, same
  ranking, no second implementation.
- **iOS Board tab** — the query is ignored outright, which is now what the desk
  and the iPad do with the whole board. The Inbox's slide-over reads `inboxTasks`
  and so is out of the query's reach whatever tab is under it.
- **A saved view on the phone** — narrowed, because searching there should narrow
  a view rather than replace it, and the phone's field is a tab you go to rather
  than a panel over what you were looking at. A view can be open with the tab bar
  on Board and no field in sight, so `showsMobileFilterNotice` is true there and
  the surface shows a "Filtered" indicator that clears it. The narrowing happens
  at `mobileTasks`, through `BoardStore.narrowed(_:)`, rather than inside
  `tasks(in:today:)` — which is what keeps it off the desk's copy of the same
  view.

`mobileAppliesQuery` answers the question for the current phone surface;
`clearQuery()` is what both clear buttons, the indicator and `reveal` call. The
query is session state, so clearing it registers no undo step and needs no save.

### The panel is an overlay, not a `.popover`

A real popover is its own window on macOS and its own presentation on iPadOS, and
both take first responder as they open — which drops the keyboard out of the
field the reader is still typing into, one character in. Measured on both. What
is drawn instead is a panel with a popover's radius, border and shadow, laid out
by `BoardToolbar` against the field's own measured frame (`fieldFrame`, in the
bar's coordinate space) so it hangs under the field wherever the fold has put it.

Two pieces of that are worth writing down because both were wrong first:

- **The z-order belongs to the call site.** The board and the inspector are the
  bar's *siblings*, one stack up, so a `.zIndex(1)` written inside `BoardToolbar`
  orders the bar against its own contents and not against them. With it there the
  panel drew underneath the inspector and was invisible from the moment a card
  was selected. `MacRootView` and `PadRootView` put the `.zIndex(1)` on the bar.
- **The overlay proposes the bar's own height**, which is 50pt, and a scroll view
  offered 50pt takes it: the panel drew one row and scrolled the rest, with its
  ground and shadow drawn around that one row. `.fixedSize(horizontal: false,
  vertical: true)` is what makes it ask for the height it wants; `Metrics.maxHeight`
  is the cap.

↑/↓ walk the list and Return takes the highlighted row. They are pressed in the
*field* — the panel never holds focus, which is the point — so `BoardToolbar`
owns the highlight and `SearchResultsPanel` scrolls to whatever it names.

## Saved views and the archive

`SavedView` is a standing filter over the whole board, shown in place of the
columns. `BoardStore.activeView` selects one; **which** view is on screen is
session state, while the views themselves are board data (v11).

### The views are the user's, and the seven are seeded

**They used to be an enum**, seven hand-written predicates in the source: the same
seven on every install, unnameable, unorderable and unchangeable. They are rows in
the board file now. A view can be made, renamed, given a different glyph,
re-ruled, reordered and deleted, and the built-in seven are seeded rows in that
same list rather than a separate kind of thing — which is what buys one code path
for the sidebar, the counts, the empty states and the surface.

| View | Rule, as criteria |
| --- | --- |
| Inbox | not archived **and** not done **and** board *is the Inbox* |
| Today | not archived **and** not done **and** due *on or before* 0 days |
| Upcoming | not archived **and** not done **and** due *after* 0 days |
| High priority | not archived **and** not done **and** priority *at least* High |
| Due this week | not archived **and** not done **and** due *is this week* |
| Recently updated | not archived — sorted newest-updated, capped at 20 |
| Archive | archived — sorted newest-filing |

**The two implicit exclusions became explicit, and that is the point.** The enum
quietly dropped archived cards from everything but the Archive, and Done from
everything but two, in a `guard` above its own table — rules nothing on screen
ever stated. A seeded view carries them as criteria the user can see and delete.
A view does what it says it does.

**A rule is a tree, not a list with an operator per row.** `ViewRule` is either a
criterion or a group that joins its children with *all* or *any*, and a group can
hold groups. That is what lets `due ≤ today AND (High OR BUG)` be written down and
told apart from `(due ≤ today AND High) OR BUG`. A flat list carrying AND on one
row and OR on the next cannot: it has to pick a precedence, and then the rule
reads one way and means another. The editor offers one level of nesting — two
brackets inside a 520pt panel is a rule nobody can read back — while the model
nests to any depth, so a file carrying a deeper tree still evaluates and draws.

**The panel is a size on the desk and a sheet everywhere else.** On macOS the
editor is 520×620 and that *is* the panel. Under a finger it is a sheet, and a
sheet has to be the size of the sheet: the 620pt cap was applied on every
platform, so on a 402×874 phone the editor drew as a squat card centred in the
presentation with a band of its ground above and below it, the last criterion
clipped and nothing to scroll it with. `Metrics.width` and `Metrics.height` are
both optional now, and `nil` means *whatever this has been given* — the frame
fills in both directions, which is also what makes the editor's own ground reach
the sheet's edges instead of letting the presentation's white through at each
end.

**An empty `all` group matches everything**, deliberately. A view with no criteria
is one being written, and the alternative opens every new view on an empty state
that looks like a bug and clears the moment the first criterion lands. `all` over
an empty set is true in every other language that has the question. An empty `any`
group genuinely excludes everything, which is why the editor never makes one — a
new bracket starts with a criterion already in it.

**Equality ignores the ids**, on both `ViewRule` and `ViewCriterion`. An id is a
row's identity for `ForEach` and nothing else, and `SavedView.seeded(_:)` mints a
fresh tree on every call — so with the synthesised `==` the seeded seven were
never equal to themselves, `BoardMutation`'s before/after comparison read every
no-op as a change, and every undo-step count in the suite came out one too high.
That is what the failure looked like from the outside: thirty tests about columns,
boards and the archive failing at once, none of them about views.

**The criteria the editor offers** — twelve fields, and the comparators each one
answers: due (*on or before* / *after* / *within the next N days* / *is this week*
/ empty / not empty), priority (*at least* / *at most* / is / is not), completed,
archived, board (*is the Inbox* / *is any board* / is / is not), column, label
(includes / does not include / empty / not empty), title and description (contains
/ does not contain), last updated and created (*within the last N days* / not), and
sub-tasks (*has some left* / *all done* / empty / not empty). Plus an order — board
order, due soonest, priority, recently updated, recently created, recently
archived, title — and an optional cap.

`SavedViewSeedTests` is the acceptance test for all of it, and it is written the
only way the question survives its own answer: **the enum's predicates are
transcribed into the test** and each seeded rule is checked against them, card by
card, over every meaning of a week, on a live board and on one with things filed
away. If the vocabulary were short of a comparator or a way to join two clauses,
the shortfall would show up here as a seeded view that cannot say what it used to
say. It also asserts the other half — that every criterion in every seeded rule is
a pair the editor's own pickers can produce, since a seeded rule reaching for
something the interface cannot build would be a view the user can see and not
rebuild, which is the one thing this change was for.

**Deleting a view asks nothing**, unlike deleting a board. A board holds work; a
view holds a rule, so the worst a mistaken delete costs is the rule — one ⌘Z, and
for a seeded one also one press of **Restore Built-in Views**, which puts back only
what is actually missing so pressing it twice is not two Archives. There is no
trash for a view: a `TrashedItem` holds work, and a view holds none.

**The surface carries the view's id, not the view.** `BoardSurface.view(SavedView.ID)`
— a surface holding a copy would go on drawing the rule the user had before they
opened the editor, and a surface holding a *deleted* view would draw a list nothing
can reach. `MacSavedViewList` and `PadRootView` look it up on every draw; `apply`
puts the surface back to the board when an undo takes the view away.

**Two of the seven are places rather than filters** — the Inbox and the Archive —
and they are in this list anyway because what a person does with them is
identical: pick the row, read the list. The predicate that names each is simply
exact rather than approximate. The Inbox is the only one with a second face: the
panel that stands beside the board. The two are the same cards in the same order,
which is why it is one of the views `sort` leaves alone — two lists of one set of
cards that disagreed about their order would be a bug people can see, and
`SavedViewTests` asserts they agree.

**The phone leaves the Inbox out of both its lists** (`SavedView.phone` and
`.phoneFilters`). It has a tab for it and a drawer row above the boards already,
and a third route to one place on the smallest screen is noise rather than
convenience. The desk and the iPad list all seven, because there the row and the
panel are genuinely different things: one replaces the board, the other stands
beside it. The View menu names them apart for the same reason — **Inbox Panel**
is the toggle, **Inbox** under it is the destination.

All except Recently updated and the Archive exclude Done; all except the Archive
exclude archived tasks — including a card that was in the Inbox when it was filed
away, which is what the shared `isArchived == (self == .archive)` guard is for. **Today includes overdue on purpose** — work that
slipped past its date must not vanish from the one list a person checks daily.
There is one spelling of that count, `count(of: .today, today:)`, and nothing
else — a second name for one number is how the badge and the list drifted apart
in the first place.

`tasks(in:today:)` applies the predicate, the ordering and the cap — and no
longer the query, which the phone puts on top at its own call site (**Where the
query still applies**); `count(of:today:)` is the view's **membership** and has
never been narrowed by the query, which would make it report the search rather
than the view. The ordering is a stable sort: "Archive completed" files a column's
worth of cards on one instant, and `sorted(by:)` would order those ties
arbitrarily and differently on each render.

The two count pills answer different questions, and are fed from different calls
on purpose:

| pill | source | why |
| --- | --- | --- |
| macOS sidebar row, iOS drawer row | `count(of:today:)`, membership | a badge on a destination: how much is *in* the view |
| the flat list's own header | the list it heads, resolved once | it sits on top of the list, so it is read as that list's length |

A header pill fed by membership reports "1" directly above "Nothing here matches",
which makes the search look broken rather than the view look full. Both headers
now resolve the list once and hand its length up — `MacRootView.body` into
`header(count:)`, `PhoneRootView.body` into `PhoneHeader(listCount:)` — so the
caption and the rows under it are the same array by construction. With no query
running the two pills are the same number for every view; the query is the only
thing allowed to part them.

`archive(_:)`, `unarchive(_:)` and `archiveCompleted()` are undoable, and an
archived task keeps its column and stays in the file — it is simply not part of
the board — and comes back where it was. `archiveCompleted()` is one step, so a
user tidying up after a week presses ⌘Z once rather than once per card.

**In the Archive the verb is Restore, and it is the only one.** A filed card is
not work in progress, so its completion toggle is not drawn: `BoardTaskCard`
answers `drawsToggle` false, which yields nothing from `completionToggle` *and*
drops the gutter it was drawn over, so the Archive's rows close up instead of
every one of them keeping a hole. One property rather than two conditions, so
the overlay and the space beneath it cannot disagree — the same one the **Tick
cards off from the board** switch flips, which is why that switch closes the
same gutter the same way. `PhoneTaskCard` keeps its gutter here and puts a
Restore disc in the same 22pt circle at the same 44pt target, and the switch
does not silence it: Restore is a filed card's only way back. The context menu offers Restore *in place of*
Complete/Reopen — at the head of the menu, where completion sits everywhere else
— and the macOS rotor action for completion is suppressed. Left live, the tick did
two invisible things: it moved the card to Done — silently choosing the column it
would reappear in — and on the way in it ticked off whatever sub-tasks were left.
Neither showed, because the Archive is ordered by `archivedAt` and the row did
not move.

**The store owes the same answer, so no surface can put the hole back.**
`complete` and `reopen` both begin `guard let task = self[id], !task.isArchived`
and return having changed nothing and cost no undo step. Hiding a control is a
view's opinion; refusing the mutation is the rule.

**Filing is not touching.** `archive`, `unarchive` and `archiveCompleted` must
leave `updatedAt` exactly where it was, which is why `update(_:log:stamping:_:)`
carries a `stamping` flag and those paths pass `stamping: false`. The rest of the
bookkeeping still happens — `markChanged` bumps the per-task revision and the
board revision, so the column grouping and the search memo keyed on them
invalidate and the board stops matching text it no longer shows. Filing is the
*only* exception: every other mutation changes what the card says and stamps
normally, `deleteLabel` included, because taking a chip off a card is a visible
change to that card.

The **"This week" meter** — which **no surface draws any more**: the macOS source
list gave it up first and the iOS drawer has now followed, so
`weeklyShippedCount(today:)` and `weeklyProgressFraction(today:)` are store API
with tests (`ArchiveTests`, `DayRolloverTests`) and no reader. They are kept
rather than deleted because the window is the hard part and a later surface
would want exactly this — it is a rolling seven-day window on `updatedAt`: shipped
(in Done, touched in the last seven days) over touched (in the last seven days).
It was `doneCount / tasks.count` over all tasks ever, which only climbed and
stopped meaning anything after the first fortnight. The accessors say so —
`weeklyShippedCount(today:)` and `weeklyProgressFraction(today:)` — and both take
the day, so the window turns over at midnight under a running app. Archived tasks
**are** counted here, the one place the archive is not subtracted: archiving is
filing rather than un-shipping, and its affordance sits on the Done column header,
so a meter that fell to zero the moment the user tidied up would punish the action
standing next to it. Filing does not move `updatedAt` either, so the reverse
cannot happen: a card filed today that shipped last month stays outside the
window rather than being counted as this week's work. The button beside the meter
moves it in neither direction.

### Reaching a view, and leaving it

A view replaces the board with **columns of cards** — `TaskColumnsView`. Cards in
it carry a **column chip**: the
column's `dot` on the neutral tone the due chip uses, because a second coloured
pill reads as another label. It is the one thing a card away from its own column
no longer says, and it is off on the board, where the heading above has just said
it. An **unfiled** card gets the chip too, reading "Inbox": a view can hold cards
from any board and the Inbox at once, and leaving the chip off would ask the
reader to infer "unfiled" from a gap. The one place the chip is suppressed is a
list that is *only* the Inbox — the desk's panel and the phone's slide-over —
where every row is unfiled and the panel is already titled Inbox.

#### The views wrap into columns

**The app is wide, and a saved view was the one surface that answered by being
tall.** A board is a strip of columns; Today, the Archive and the rest were a
single 620pt run of cards down the middle of a window with the other two-thirds
empty. The cards were never the problem — a saved view has always drawn
`BoardTaskCard`, and only stretched it — so what changed is the arrangement.

A column now fills to the bottom of the window and the next card starts the
column to its right, at the board's own column width, gap and gutter:
`TaskColumnMetrics` reads all three off `BoardColumnView.Metrics` and
`BoardScrollView` rather than picking them again, so a card does not change size
crossing between the two surfaces.

**The two flows go opposite ways, and the shape of the screen decides which.**

| surface | flow | scrolls |
| --- | --- | --- |
| macOS, iPad | down, then across | sideways, like the board |
| iPhone, landscape only | across, then down | down, as it always did |
| iPhone, portrait | one column — `TaskListView`, unchanged | down |

The phone is the exception because 390-odd points of height is two cards: wrapping
downward there would mean paging sideways through columns two deep, which is a
worse read than the list it replaced. Wrapped across, the same width holds two
cards a row on a 17 Pro and three on a Pro Max — `.adaptive(minimum:)` is handed
the board's own 250pt landscape page and works the count out, so no phone is told
a number. Two rather than three on the 17 Pro is the margins: 874 less 62 either
side of the sensor housing is 750, and less this surface's own 16pt either side
is 718. The board buys its third page by spending no horizontal margin at all,
which a surface with no column ground cannot do.

**Where the wrapping is decided is a pure function**, `ColumnFlowLayout.columns(of:
into:cardSpacing:)`, split out of the `Layout` because a `Layout`'s `Subviews`
cannot be built by a test — the same arrangement `SidebarRoomTests` has with
`yields(to:in:)`. Every card is measured at the column's width rather than
assumed to be a standard height: a card's height is its title's line count plus
whether it carries a description, chips and a checklist bar, so a fixed number of
cards per column would be right for one board and wrong for the next. The packing
is greedy and deliberately not balanced — a saved view is *sorted*, so evening up
the columns would be reordering the view to make it look tidy.

**It is not a `List`, and that costs nothing here.** `TaskListView` stays one for
the reason its own doc gives: a `List` handles drags inside its own bounds, so
swapping the container under a surface that takes drops would change what a drop
does. This surface takes none — `allowsCardDrag` is `activeView == nil &&
sortOrder == .manual`, so dragging is off in every saved view, and
`ReorderableCard` reads the same flag before it offers a lift.

Keyboard focus is untouched, because the *order* is untouched: ↑/↓ walk the same
array, which now happens to run down a column and on to the top of the next. A
card focused by a key can be a screen away sideways rather than a screen away
down, so the surface answers `BoardReveal` exactly as the board's columns do.

`TaskListMetrics.pad` went with the change — the iPad's saved views were its last
caller. `ColumnFlowTests` pins the packing and `PadListMetricTests` pins where the
numbers come from.

"Build it once" took a second pass to actually mean it. The phone had a list that
merely *resembled* the shared one — its own `List`, down to a private copy of the
row modifier — which left `TaskListView` with a single macOS call site and the
duplication the whole item exists to remove. What absorbs the phone's list is a
second generic parameter:

```swift
struct TaskListView<Card: View, Trailing: View>: View
```

`trailing` is a `@ViewBuilder` of rows drawn after the cards, inside the same
`List` and under the same row modifier, so the phone's dashed "add task to…" row
and its empty state scroll with the cards and inherit their margins rather than
carrying a second copy of them. Three things about it are load-bearing:

- **The no-trailing call site is unchanged.** Two `where Trailing == EmptyView`
  overloads keep macOS spelled exactly `TaskListView(tasks: tasks, metrics: .desk)`.
- **Nothing is dropped by rendering an empty view.** The rows are skipped by a
  static `if Trailing.self != EmptyView.self`, because an `EmptyView` wrapped in a
  row modifier is a view like any other and a `List` is entitled to give it a
  row's worth of insets.
- **Row actions arrive through the card, not the list.** `PlatformTaskCard` is
  the one place a `#if os()` picks the platform's card — macOS draws `ListCard`,
  iOS draws `PhoneTaskCard` with `PhoneTaskRowActions`. List-row traits are read
  off the row's own view, so this is where SwiftUI looks for them; that mattered
  for `swipeActions` while there were any, and still does for the context menu.

`PhoneRootView.taskList` is now a call to that view and its `BareRow` is gone.

- **macOS** — the sidebar's view rows are real `Button`s with a live `CountPill`,
  the active one styled `palette.accentSoft` exactly as the active board row is.
  Clicking the active row returns to the board, and so does the `← Board` button
  in the list's own header. The Archive sits slightly apart from the five
  filters, because it is a place things go rather than a filter over the board.
  ⌘N leaves the view first: the composer lives in a board column, so from a flat
  list it opened a row nobody could see. Each row leads with
  `SavedView.symbol` — the glyph that view's empty state and the phone's drawer
  were already drawing, so a row and the surface it opens carry one mark rather
  than each picking their own. The **boards** above them keep a coloured dot
  instead, which is the truer split: a board's mark says *which* board and is the
  user's to recolour, while a view's says what the view is for and is the same on
  every install. Every symbol in the list is drawn in a `Metrics.rowGlyph` slot,
  Labels, Trash and Settings included, so one column of glyphs runs down the list
  — a `calendar` is half again as wide as a `sun.max`, and left to themselves the
  labels stagger. The rows are `accessibilityRepresentation`-substituted for the
  same reason the ones under **Manage** already were: an `Image` among siblings
  inside a button's label is published as an element of its own however it is
  hidden.

  **The row that opens the label manager is called Labels**, not *Manage labels*.
  Every other row in this list is named for what it is rather than for what
  pressing it does — the boards are not "Open board", the Archive is not "Show
  archive" — and it was spending the word *manage* twice while standing under a
  heading that said Labels. The heading spends it once now, on a section that
  holds the labels, the Trash and Settings — **the same three rows in the same
  order on all three platforms**, which they were not. The desk's settings row
  was `#if os(iOS)` on the reasoning that ⌘, and the app menu are its door and a
  second one would be a duplicate; that is true of the *key* and not of the
  list, and it left the desk two rows where the iPad had three. The phone's
  drawer headed its own section **Labels**, held one row called *Manage labels*,
  had no way to the Trash at all, and kept Settings loose under the lists rather
  than in a section. `ManageSectionTests` reads both files and holds the three
  surfaces to one answer. The desk's row is a `SettingsLink` rather than a flag,
  because `isShowingSettings` raises the sheet the phone and the iPad use and
  does nothing at all on macOS, where Settings is a scene the system opens.
- **iOS** — the drawer's Views list carries the same rows, and the `…` menu in
  the header carries them again for a user who is not in the drawer. The header
  grows a bar naming the open view with a way back.

These rules are the iPhone's alone:

- **The Inbox comes up from the bottom** — `PhoneInboxSheet`, a panel over the
  board rather than a place instead of it. It was the middle of three tabs, and a
  tab is somewhere you *go*: going to the Inbox meant leaving the board, and
  coming back meant remembering which board you were on. The Inbox is precisely
  the list you reach for *while* working on one, which is what the desk and the
  iPad answer with a panel beside the board; a phone has nothing to put a panel
  beside, so this one goes over the top. `PhoneTab` is `board` and `search` now,
  the Inbox slot on the tab bar is a **toggle** driving the same `isInboxOpen`
  the other two platforms use, and it reads as current whenever the panel is up —
  over a saved view included, because a panel over the top is showing whether or
  not a view is under it.

  It is **a real `.sheet` held at a detent, the same kind of thing as
  `PhoneDetailSheet`** — and it was hand-rolled until it wasn't. The reason for
  hand-rolling was measured and is still true: a sheet below `.large` floats
  inset and is *scaled* to compensate — 0.9602 on a 402pt-wide phone — so every
  44pt control in it lands at ~42.2, and the factor differs per device so no
  padding buys it back (see **Touch targets**). The editor pays that knowingly
  at four fifths; this pays it at nine tenths, because everything the
  hand-rolled panel did was a worse copy of what the system already does.

  Four pieces of this file went away with the swap — the scrim and its fade, the
  insertion and removal transitions, the live drag offset with its
  spring-back-or-let-go rule, and the `scrollDisabled` that decided whether a pan
  belonged to the list or to the panel — and what arrived is the platform's own
  physics: rubber banding, a flick that carries, the drag handed to the list
  while the list can use it and taken back at the top of it, `.isModal` without
  being asked, and a grabber drawn by `presentationDragIndicator` rather than by
  a `Capsule` of ours.

  **On its side it is not a sheet at all, and that is the second half of the
  story.** A sheet in a compact height ignores its detent and is laid out at the
  whole screen, so a phone turned sideways drew the Inbox as a full-screen page
  with cards stretched 874pt across. Capping the panel at the screen's short edge
  — that phone's own portrait width, `PhoneNavDrawer.width(in:screen:)`'s rule
  and for its reason — fixed the panel and not what it stood on. A sheet that
  covers the screen has the view that presented it **taken out of the hierarchy
  underneath**, so the board is not behind the panel and cannot be put there:
  measured three ways — a clear presentation background, the app's own ground
  painted behind the panel, and `presentationBackgroundInteraction(.enabled)`,
  which sounds like it should keep the presenter alive and does not — what is
  behind a compact-height sheet is the bare window, white in light and black in
  dark. A scrim over that is not a wash but a slab, and the panel was standing in
  a hole rather than over anything.

  So on its side the Inbox is an **overlay of `PhoneRootView`'s**, which is the
  shape `PhoneNavDrawer` already has: `palette.scrim()` with the live board under
  it, and the panel over that. What it costs is the two things the sheet was
  doing for nothing, and both are hand-rolled back: a `Capsule` at the head of
  the panel carrying a `DragGesture` — on the handle rather than the whole panel,
  because a drag over the cards belongs to the list and a sheet arbitrates that
  for itself where an overlay has to be told — and `.isModal`, plus an
  `accessibilityHidden` while the editor is up, because an overlay is a *sibling*
  of the window's content rather than something underneath a presentation and
  both the panel's × and the editor's are labelled Close.

  **Which shape it is in is one flag answering two questions**, and the handover
  is the subtle part. The sheet is driven by view state (`showsInboxSheet`)
  rather than by a binding computed off `store.isInboxOpen`, because a computed
  binding cannot tell apart the two ways it goes false: turning the phone takes
  the sheet down, SwiftUI reports that back as a dismissal, and a guard inside
  the setter reads whichever `self` the binding it is holding captured — which
  may be the one from before the phone turned. Measured, rotating with the panel
  up closed the Inbox instead of handing it over. Three `onChange`s do it
  instead, and they run against the values the body has now.

  **A card tapped in the Inbox opens the editor over it**, and that is the one
  thing the swap put at risk: a sheet is presented *by* whatever is on screen,
  and the root cannot put a second one up while this one is over it — the tap
  would do nothing at all. So `phoneTaskDetailSheet` has two call sites with one
  rule between them: the root holds it while the Inbox is shut, the Inbox holds
  it while it is open, and exactly one is live. `PhoneNavDrawer` hosts its own
  sheets for the same reason and says so in the same words.

  **The drag cannot be tested from here while it is the system's**, which is why
  the four tests that covered the hand-rolled version went with it. A synthetic
  `press(forDuration:thenDragTo:)` does not drive a system sheet's pan — a
  recording of the simulator shows the sheet perfectly still through a 500pt drag
  that dismisses it under a real finger. `UITests/InboxPanelTests` pins what is
  left and reachable: the height, the × , the editor coming up over the Inbox and
  the Inbox still being there afterwards, and the width after a rotation.
  `DetailSheetHeightTests` reaches the same wall for the editor and answers it
  the same way.

  On its side the wall is not there, because the gesture is ours again: the same
  suite turns the phone, pulls the handle down 220pt and asserts the panel is
  gone. A `DragGesture` of our own is something a synthetic drag *can* drive,
  which is the one advantage of having to write it.

  It sits **under** the drawer in the overlay order,
  because the drawer is the way to a *board* and a board list half-covered by the
  Inbox is the wrong way round; the drawer's Inbox row closes the drawer on its
  way. Its height is a **share of the screen — 90% of it** — rather than the
  height of what is in it: the list inside is `TaskListView`, `TaskListView` is a
  `List`, and a `List` reports no useful intrinsic height, so under `fixedSize`
  it collapses and the panel draws as a header over a hole. It was two thirds and
  is most of the screen now, because the Inbox is a list you work *through* and
  two thirds of a phone is four cards and a scroll for the rest. What the strip
  along the top buys is the thing a panel has over the page this used to be: the
  board is still there, and it is obvious that tapping it puts you back.

  **The condition lives inside the panel, not around it.** `PhoneRootView` used
  to hold `if store.isInboxOpen { PhoneInboxSheet() }`, with the move and the
  fade written on the two views one level further in — and neither ran: a
  transition belongs to the view that is *itself* appearing, and on a subtree
  that arrives all at once SwiftUI animates the outermost view and ignores what
  is written inside it. So the panel faded up at its final height in about four
  frames, which reads as no animation rather than as a quick one. A recording of
  the simulator, stepped frame by frame, is what settled that — the same
  instrument the drop flash was found with. With the `if` inside, the scrim and
  the panel are each inserted in their own right and keep their own arrivals.
  **`PhoneNavDrawer` is built the same way and has the same fade**; it is next.
  Timing stays `PhoneRootView`'s `motionAnimation`, which is what makes both of
  them nothing at all under Reduce Motion.
- **The chips strip follows the column you are on.** Four columns with ordinary
  names overrun a phone — on the seed board the strip clips at 370pt and the Done
  chip runs to 389 — and the strip never moved, so paging to the last column
  highlighted a chip with 19 of its 70 points off the screen and left it there.
  It is a `ScrollViewReader` now, scrolled on every change of `mobileColumnID`
  and once on appear, because a board is not always opened on its first column.
  `scrollTo` with **no anchor** is the minimum scroll that makes the chip whole
  and no scroll at all when it is whole already — the board's own rule on the
  desk, for the reason `BoardScrollView` gives: centring instead would shuffle
  the strip under every page turn, including the ones that needed nothing. The
  chips are the only thing on the surface that names the column you are on, so
  `UITests/ColumnChipTests` matches them by their combined `Name, count` label —
  a page heading names its column too, and it is static text rather than a
  button.

- **Picking a tab leaves the view.** `mobileTasks` lets a view outrank the tab,
  so without this, tapping "Board" showed Today. `selectTab(_:)` and
  `quickCapture()` both clear it, and no tab is highlighted while a view is open
  — highlighting one would name a place that is not what is on screen.
- **The "+" raises nothing but the card it makes.** `quickCapture()` used to
  open the Inbox panel as well, on the reasoning that the card lands there and
  should be visible once the sheet closes. In practice it opened a second
  surface *behind* one the user is already typing into: never seen while it
  mattered, and left standing over the board afterwards for somebody who never
  asked for it. Capture is one act and it moves the user nowhere. The card is
  still in the Inbox, and the sheet says so while it is being typed into — the
  Move-to row names where it lives. Leaving a saved view stays, because that is
  a different question: a filter the new card is unlikely to match is not a list
  to strand somebody in whether or not a panel comes up over it.
  `UITests/QuickCaptureTests` checks it **after the sheet closes**, which is
  where it showed — a presented sheet marks what is under it inaccessible, so a
  test that looked while the sheet was up would have passed against the bug.
- **The `…` button is a real `Menu`, and it holds only what has no other home.**
  It was a decorated `Image` — no action, no accessibility label, no tap target —
  sitting beside a hamburger that worked; it now has a 44pt target. What is in it
  is **Board settings**, Archive completed, Manage labels, the Trash and
  **Settings**. Board settings replaced *Rename board* by holding it: renaming is
  one field of a sheet that also carries the board's colour and all of its
  columns. **The first row names the surface that is on screen**: on a saved view
  it is **Edit View…** instead, which raises that view's own editor. It offered
  Board settings there — the settings of the board standing *behind* the view,
  which is not what the reader is looking at — and this menu is the phone's only
  door to a view's rule that is not the drawer. The editor is raised through
  `BoardStore.editingViewID` rather than presented by the menu, for the drawer's
  reason: a menu is gone by the time the sheet would open.
  What was taken out of it is the hamburger's: **Switch board** stood a thumb's
  width from a drawer that lists every board with its dot and its count, and the
  whole **Views** section stood beside the same drawer's views and the Archive
  under them — a second, shorter, worse copy of the panel next to it. **Clear
  search** went with them, because the field has an × and the surfaces without
  the field have the filtered indicator under this header: a filter is never
  invisible (1.11), so a control that undoes it is always already on screen.
  Settings arrived by the same rule in reverse — it was reachable *only* by
  opening the drawer and scrolling to the foot of it. `UITests/BoardMenuTests`
  pins the three removals by name, the survivors, and the new door.
- **Column chips are on Search and every saved view, never the Board tab**
  (`showsMobileColumnChips`), where the strip in the header names the column.
  The Inbox's panel drops them too, and makes that call for itself: every card in
  it is unfiled, so the list would read "INBOX" under a panel titled Inbox.
- **Everything below the drawer's title scrolls, and the indicators show.**
  Pinning the weekly summary and the accent picker outside the `ScrollView` left
  the rows between them whatever height was left over — 481pt of viewport for
  620pt of rows on a 402x874 phone, so the Archive row was clipped and "Manage
  labels" sat 59pt past a fold that hidden indicators refused to admit to. The
  bar to clear is the *smallest* supported iPhone, not the largest: on a 375x667
  device one swipe now reaches "Manage labels" and the accent swatches, and that
  is the end of the scroll.
- **84% of the screen's short edge, not of the screen's width.** The design's
  fraction was read against the container, which is the same number in portrait
  and a different surface on its side: an iPhone in landscape is 874pt across,
  so the board list came out at 734pt over a sliver of board. It is the short
  edge that a drawer is a fraction of, and the short edge does not change when
  the phone is turned — 338pt on a 17 Pro, 315 on an SE, held either way up.
  Not a fixed maximum, because the number a drawer may not exceed is *that
  phone's* own portrait width and no other. `PhoneNavDrawer.width(in:screen:)`
  is the sum and `DrawerWidthTests` holds it; the screen is measured once by
  `PhoneRootView`, outside the safe area on purpose — inside it, landscape's
  short edge is missing the home indicator's 21pt and the drawer would come out
  narrower turned than upright. The pan that drags the drawer in asks the same
  function, or the panel trails a third of the way behind the finger.
- **The drawer is modal to VoiceOver as well as to the eye.**
  `.accessibilityHidden(store.isNavDrawerOpen)` on `PhoneRootView`, applied
  *before* the `.overlay` so it takes the board and leaves the drawer;
  `.accessibilityAddTraits(.isModal)` on the drawer; and an
  `@AccessibilityFocusState` that moves focus to the drawer's heading on open.
  Without it the board underneath stayed hittable while every drawer row did not,
  so VoiceOver could drive the board it could not see and not the drawer it
  could.


### Where you are, said once

**A saved view takes the title.** Open Today and the title bar says *Today* under
the view's own symbol, on all three shapes — `BoardToolbar.viewTitle` on the desk
and the iPad, `PhoneHeader.titleLabel` on the phone. It used to go on naming the
board, with the view named in a strip *underneath* it: two answers to one
question, and the one in the larger type was the wrong one. The board's name is
still a text field you rename in place; a view's is not, because a view is renamed
in its own editor where its rules are, and a title that is a field on one
destination and a label on the next is a title nobody can trust to be either.

**The strip is gone**, and its Back to Board button with it. That button was a
second way out of a place the source list, the drawer or the tab bar is already
one press from — and on the iPad it never existed for exactly that reason. Its
count pill went too: it counted the rows underneath rather than the view's
membership, which is a distinction worth drawing when the number is sitting on
top of a list and not worth a strip of chrome when it is not. The sidebar row's
badge is still the membership. The board gets back 46 points on the desk, 60 on
the iPad and a 44pt row on the phone.

**A destination row is not a toggle.** Pressing the row of the view you are
already on used to send you back to the board — the sidebar's did, and the phone
drawer's put the tab bar's own place back. One control with two meanings and no
way to tell which one you are about to get; and since the row is how you *arrive*
at a view, pressing it twice is something people do by accident constantly. It
does nothing now, which `BoardStore.surface` was already prepared for: its `didSet`
refuses an assignment that does not change anything, so arriving where you are
costs no write and no preference update. `UITests/SavedViewTitleTests` holds all
three claims, and holds them on the surface they are about — none of them is
something a store can be asked, since `activeView` reads the same either way.

## Selection, commands and shortcuts

**The selection is a set.** `BoardStore.selection` is a `Set<TaskItem.ID>`: the
board offers a range (⇧-click), a toggle (⌘-click) and Select All, and the bulk
commands those exist for. `selectedID` survives as a computed face on it that
returns the one selected task — and `nil` for none *and* for several, which is
what keeps every consumer working unchanged, because the inspector showing a task
when exactly one is picked and its empty state otherwise is the right answer for
a multi-selection too. Assigning to it replaces the whole selection.

Writing the set is what ends the editing sessions a surface left behind: a
surface that has moved to another card cannot end them there, and a session
nobody will ever end silences that card's picker logging for good. The rule is
measured against `selectedID` rather than the set, so picking a *second* card
takes the panel off the first as surely as picking another one would.

A range is measured against the ids the surface passes in, in the order it is
drawing them — the range a user means is the one they can see, which is neither
the board's array order nor a set's. The anchor stays where it was put, so a run
of ⇧-clicks sweeps out from one card rather than growing from the last.

**Bulk commands are one ⌘Z, not one per card** — the whole point of a
multi-selection. `move`, `complete`, `archive`, `deleteTasks`, `toggleLabel`,
`setPriority` and `setDue` each take a `Set<TaskItem.ID>` and wrap the
single-card mutation they are built from in one `undoable`; the nested step
collapses into it. Built that way rather than copied, because a second hand-written
copy of each rule is what eventually drifts from the first. They act in board
order, so cards moved together arrive in the order they were in, and they name
themselves in the plural, so the Edit menu says how much a ⌘Z is about to take
back. A bulk label goes *on* until every selected card has it and only then comes
off — toggling each card independently would leave a mixed selection exactly as
mixed as it started. `addTasks(to:titles:)` joined them for ⌘V: one `undoable`
around the loop, and the selection and draft state moved once *after* the step
closes rather than per card inside it.

Three invariants of those paths, each of which fails silently and each of which
had a surviving mutant:

- **Board order.** Every bulk command acts in the order the board has the cards,
  never the set's. A test that pins two cards is a coin toss rather than an
  assertion — `Set` hashing is seeded per process — so pin four and pin every
  resulting position.
- **Placement.** The bulk move goes straight to `performMove`, so the
  `isPlaceable` pairing check the singular `move` makes on the way past is the
  bulk path's own to make, or a selection lands on board A in board B's column.
- **The anchor.** ⌘-clicking a card out of the selection takes the anchor with
  it, or the next ⇧-click sweeps from a card that is no longer picked.

**A bulk command acts on the cards it applies to and titles itself from those.**
`complete(_:)` *is* `completeTargets(_:)` and `archive(_:)` *is*
`archiveTargets(_:)`, so the count a menu item promises and the list it acts on
are the same call and cannot drift — which they did: three cards with one already
in Done gave a menu reading "Complete 3 Tasks" and an undo step called "Complete
Task", having moved two. `canComplete(_:)` / `canArchive(_:)` answer for one card
and are the same predicate the singular mutations guard with, not a second copy
of it. Delete and Copy act on the whole selection, so `selectionCount` is the
right number for those.

**One shortcut vocabulary, in one place.** `Sources/Model/AppCommand.swift` is an
enum of every command with its localised title, its keys, its menu and the block
of it, which cards it applies to, and who performs it. (`needsSelection` survives
as the coarse half of that last question — "is this aimed at a card at all" — and
is no longer what a menu item asks.) The menu
bar, the board's key handlers and the keyboard-shortcuts sheet are all built from
it, because three surfaces that each spell the vocabulary out separately will
drift — and a sheet claiming a shortcut the menu does not have is worse than no
sheet at all.

- **⌘N is New Task and ⇧⌘N is New Board.** ⌘N used to sit on a toolbar button
  while the default File menu still advertised ⌘N as New Window, so the menu and
  the key disagreed about what the app did. Replacing SwiftUI's `.newItem` group
  with these two is what settles it, and `beginAddingWhereVisible()` is what
  keeps the composer on screen: it is drawn by whichever surface owns the place
  it is adding to, so the command puts that surface up first rather than focusing
  a text field nobody can see.
- **⌘C, ⌘V and ⌘A get no menu item.** A Copy on the Edit menu takes ⌘C away from
  every text field in the app, and Select All takes ⌘A. They sit in the `.board`
  group, which is handled where the board has focus and taught by the sheet.
- **Undo and Redo are listed but not declared.** `UndoManager` already puts them
  on the Edit menu; declaring them again would put two of each there. They carry
  `source: .system` so the menu skips them and the sheet still shows them.
- **Import and Export carry no key.** Both open a panel the user then has to
  answer, so a key would buy a keystroke and cost one of the few left. They were
  `source: .unbuilt` — named and drawn disabled — until Phase F built them;
  nothing is in that state now, and the case stays so the next one is declared
  rather than omitted.
- Submenu *contents* are not in the enum. The columns under Move to Column, the
  priorities, the saved views and the boards all belong to the store and change
  as the user works; the enum names the anchor and the menu fills it.
- ⌘F reaches a search field it cannot see: `focusSearch()` bumps
  `searchFocusToken`, which the toolbar's field watches. A counter rather than a
  flag, because with the field already focused a flag is already true and a
  second ⌘F would be no change at all. **The phone's field watches it too**, and
  `selectTab(.search)` bumps it: Search is a tab you go to in order to type in
  it, and it used to arrive as an empty field with no keyboard and no caret, so
  reaching it cost a second tap that had to find the field's own 22pt band of
  text. The field opens through `focusWhenReady` like every other field in this
  app that is opened *by* something, and answers the token for the times it is
  already on screen. `UITests/SearchFocusTests` holds it: the tab, then the
  keyboard, then a letter that has to land in the field.

### The menu bar

`BoardCommands` (`Sources/App/BoardCommands.swift`) is the menu bar, **generated**
from `AppCommand` rather than transcribed from it:

| menu | items |
| --- | --- |
| **File** | New Task ⌘N · New Board ⇧⌘N · New Column… ⌥⌘N · New View… · Import… · Export… · Board Settings… ⇧⌘, · Save Board ⌘S · Sync Now ⌘R · Settings… ⌘, *(iPad)* |
| **Edit** | Undo ⌘Z · Redo ⇧⌘Z · Trash Task ⌘⌫ · Find ⌘F |
| **View** | Toggle Inspector ⌥⌘I · Toggle Sidebar ⌃⌘S *(Mac)* · Toggle Inbox ⇧⌘I · Show Trash ⇧⌘T · Labels… ⇧⌘L · Themes… *(Mac)* · Appearance ▸ · Card Size ▸ · Sort By ▸ · Previous Board ⌥⌘↑ · Next Board ⌥⌘↓ · Board · Inbox Panel · the saved views · every board |
| **Task** | Complete Task ⌘⏎ · Reopen Task ⇧⌘⏎ · Move to Column ▸ · Move to Board ▸ · Set Priority ▸ · Set Due Date… · Show in Board ⌘J · Archive Task · Restore Task |
| **Help** | Keyboard Shortcuts ⌘/ |

Nothing in `BoardCommands` names an item. `AppMenuSection` is one
divider-separated block of one menu — a menu needs more than one where macOS
splits it and SwiftUI gives each half its own placement — `AppCommand.menuSection`
maps every command to a block in an exhaustive switch, and each placement draws
`ForEach(AppCommand.menuItems(in:))` behind a single exhaustive `perform(_:on:)`.
So an item cannot be lost or gained here without the vocabulary saying so, and a
command added to the enum cannot compile until it has both a block and an action.
The hand-written list this replaced had a whole block commented out of it at one
point and nothing noticed; `MenuDeclarationTests` now reads this file as text,
because a `Commands` body has nothing to enumerate at runtime.

**Order inside a menu is the enum's declaration order**, which is what makes the
test pinning that order a test of the menu bar. The View menu reads Toggle
Inspector, Toggle Sidebar because `AppCommand` declares them that way and the
shortcuts sheet lists them that way; it used to read the other way round, which
made the pinned order a statement about nothing.

**Two menus are the app's own furniture rather than the board's.** The View
menu's middle block writes preferences — Appearance, Card Size and Sort By are
the same three controls Settings has, read through `@AppStorage` and
`store.sortOrder` so a tick beside a row follows a change made anywhere else —
and its next block steps through the boards, wrapping at both ends because a key
that stopped at the last one would need the user to know which end they were at
before pressing it. `BoardCommands.board(_:from:in:)` is that rule as a static so
a test can hold it up; a `Commands` body has nothing to enumerate.

**Some items are aimed at the board rather than at a card**, and they disable on
the same principle: `AppCommand.isAvailable(in:)` takes New Column and Board
Settings… dead when there is no board, Sync Now dead when sync is off or iCloud
is unavailable, and Next/Previous Board dead on a one-board install.

With a hidden title bar there is no Show Toolbar and no Enter Full Screen, so
the View menu is **only** what this app puts in it — placing the two toggles
`after: .sidebar` is what makes a View menu exist at all. The rest of the bar is
the system's: Close and Close All still under File, the standard Cut/Copy/Paste
and Select All under Edit, and Undo and Redo appearing exactly once each.

**An item is aimed at cards, and disables when none of them can accept it —
which is not the same as "when nothing is selected".** Being selected is not the
same as being a fit subject. `AppCommand.applies(to:in:)` answers for one card
and `isEnabled(for:in:)` for the cards an item would act on: live when *any* of
them can accept it, and then acting on exactly that subset. Complete and Archive
ask the store the store's own questions — `canComplete(_:)`, `canArchive(_:)` —
rather than restating the rule; an archived card refuses a column, a priority and
a due date as well, because it is off the board. On the Archive surface ⌘A puts
nothing but archived ids in the selection, and the whole Task menu used to sit
there fully live: Move to Column really moved a filed card from Backlog to Done,
behind the user's back, on a surface they are reading as a record. Delete Task
stays on there — a filed card can still be thrown away.

The **submenu rows** follow the same rule as the items above them: the column the
cards are already in and the priority they already have are ticked *and* disabled,
because a row that moves a card to where it already is does nothing. A mixed
selection is "current" nowhere, so every row stays live.

The title, the enabled state and the action all come off one `applicable(_:)`
call, so an item cannot promise one thing and do another. Pick three cards with
one already in Done and the menus read "Delete 3 Tasks", "Complete 2 Tasks",
"Archive 3 Tasks" — the count is `store.completableCount` / `archivableCount`,
which is `completeTargets(_:)` / `archiveTargets(_:)` counted, which is the same
call `complete(_:)` and `archive(_:)` act on. It used to title from
`selectionCount` and then file an undo step called "Complete Task", singular,
having moved two.

The View menu's lower half is the same destination list the sidebar draws: the
board, the Inbox, the saved views and the boards themselves, with a tick against
wherever the user already is, marked the way every other destination list in this
app marks it. Every surface of the app is reachable from the menu bar as a
result, which for a keyboard-only user it previously was not.

**Items aim at the focused card when a surface has the keyboard**, and at
`store.selection` otherwise: `targets` is `store.commandTargets(focusedTaskID)`
falling back to `selectedTasks`, so a focused card that is part of the selection
brings the selection with it and one that is not is aimed at alone. That is also
why ⌘⌫ and ⌘⏎ are the menu's keys rather than the card's — see **Keyboard on the
board**.

Some items ask a view for something the menu bar cannot reach itself, because the
menu bar is outside every window's view tree. `AppWindowState` is where they
meet: it holds whether the source list is showing, which column has the keyboard,
which card has it, and one flag each for New Board, Set Due Date… and Labels…. **New Board
asks the sidebar's own row** rather than calling the store itself, so there is one
answer to what making a board does: it mints one under `Board.defaultName` and
opens its settings on the empty name field. **Set Due
Date… opens a sheet**, not a submenu: the ellipsis in the title promises
something to type into, and it acts on the cards the item was aimed at — which
the item *hands over*, because the sheet used to work them out again as
`store.selection` and ⎋ leaves the keyboard on a card with nothing selected. The
item stayed live, rightly, opened a sheet titled "Due date", and Set did nothing
at all. And **⌘N adds to the
column the user is looking at** when the board has the keyboard, falling back to
`beginAddingWhereVisible()` otherwise; either way `BoardScrollView` scrolls the
composer into view, because a composer that opens off the right-hand edge takes
the focus somewhere the user cannot see. That was the whole of the old
`beginAdding(in:)` bug: it always targeted the leftmost column.

**Four items open a sheet, and the root presents it rather than the thing that
asked.** Keyboard Shortcuts, Set Due Date…, New View… and Labels… are all raised
as a flag — on `BoardStore` where a surface already owned one, on `AppWindowState`
where the menu is the only asker — and `MacRootView` and `PadRootView` present
all four. The source list has rows that open two of the same sheets and keeps its
own state for them, which is right: a row can present what it asks for. A menu
item cannot, and the list it would borrow a flag from can be hidden. **Show Trash
is the exception that proves it**: the Trash is a popover hanging off the source
list's own row, so the item brings the list out first and waits
`BoardCommands.sidebarTravel` for it to have a frame — a popover asks its anchor
for one at the moment it is presented, and a view added in the same runloop turn
has none.

### The iPad has the same menu bar

iPadOS 26 draws a menu bar for every app, and this one declared no commands into
it: the iPad got the system's default File, Edit and View with nothing of the
app's in any of them, while the shortcuts sheet went on teaching keys that
reached nobody. `.commands { BoardCommands(...) }` is now on both scenes, built
from the same vocabulary, and `MenuDeclarationTests` reads `SimpleKanbanApp.swift`
as text to say so — a one-line modifier is exactly the kind of thing that can be
deleted without another test noticing.

Everything the vocabulary holds is on both machines except three items, and each
of the three is excluded because **the platform already has that item**:

| item | whose | why |
| --- | --- | --- |
| Settings… ⌘, | the iPad's | macOS has SwiftUI's `Settings` scene, which puts its own item and key on the app menu |
| Toggle Sidebar ⌃⌘S | the Mac's | a `NavigationSplitView` is a `UISplitViewController`, and UIKit puts *Show Sidebar* on the View menu for it |
| Themes… | the Mac's | it opens a `Window`; the iPad reaches the browser through Settings ▸ Appearance |

The first two are not taste. A second item on a key UIKit has already claimed is
not a duplicate the system resolves in somebody's favour: it throws
`NSInvalidArgumentException` while building the menu, and the app **terminates on
launch**. Both were found that way on an iPad Pro 13", each taking the whole test
host down before a single test ran — which is also the evidence that the
declarations reach the system's menu bar at all, since UIKit could only object to
keys it had been handed. The iPad's own Show Sidebar moves the same split view
column, and `PadRootView` reads that movement back onto
`AppWindowState.isSidebarVisible`, so the items that need the list out — New
Board, Show Trash — still get it out.

`AppPlatform` is where the split is written down, rather than `#if os(macOS)` at
each site, so a test can ask for both answers on either machine: a menu that is
wrong on the platform you are not building for is drift nothing would otherwise
notice. The shortcuts sheet filters by it too, so neither machine is taught a key
it does not carry.

**What had to move for this to work.** `MacWindowState` became `AppWindowState`
and is owned by the app on both platforms; `MacShortcutsSheet` and
`MacDueDateSheet` became `ShortcutsSheet` and `DueDateSheet` in `Sources/Shared`,
because an item declared on both platforms cannot open a sheet that is `#if
os(macOS)`; and `PadRootView` grew the two mirrors `MacRootView` already had —
focus both ways, so ⌘⌫ can name the neighbour of the card it deleted, and the
focused column one way, because nothing outside the board sets that.

**The dispatch order is the other way round, and the answer is unchanged.**
`BoardKeyboard.menuOwnedShortcuts` takes ⌘⌫ and ⌘⏎ away from cards on the desk,
because AppKit dispatches a menu key equivalent out of `NSApplication.sendEvent`
before the responder chain is offered the event. UIKit offers the press to the
responder chain first and reaches the menu at the end of it, so on the iPad the
card answers and the menu item is what catches the press when nothing has focus —
the same act on the same card either way, because the item aims at exactly the
focused card. The set stays empty there; only the reason for it has changed.

The iPhone has no menu bar to draw any of this on and loses nothing by the
declaration: a `Commands` body it cannot show is a set of key equivalents for a
hardware keyboard, which is what an iPhone with one attached should have.

### Keyboard on the board

A card is focusable — `BoardCard` on the board, `ListCard` on the flat surfaces,
both in `Sources/Shared/BoardKeyboard.swift` and both wrapped around
`BoardTaskCard` rather than folded into it.

| key | owner | what it does |
| --- | --- | --- |
| ← → | card, board only | focus the next column along, keeping the row and stepping over empty columns |
| ↑ ↓ | card | focus within the column, clamped at the ends rather than wrapping |
| ⌥← ⌥→ | card, board only | **move the card** — the whole selection, if the focused card is in it — to the adjacent column, empty or not; focus follows it |
| ⏎ | card | open the inspector on it |
| Space | card | complete it. One card *toggles*, because that is what the tick beside it does; several complete, because "reopen three of these and finish the other two" is not something one key can mean |
| ⌘⏎ | **menu** | Task ▸ Complete Task, one-directional — which is why it disables on a card already in Done, where Space still reopens it |
| ⌘⌫ | **menu** | Edit ▸ Delete Task, after which focus falls to the card below, or to the one above if there is none |
| ⌘A ⎋ | card | select everything on the surface · clear the selection |
| ⌘C ⌘V | card | see **The clipboard** |

**⌘⌫ and ⌘⏎ belong to the menu bar, not to the focused card.** A menu key
equivalent is dispatched out of `NSApplication.sendEvent` before the responder
chain is offered the event at all, so a card claiming either would be claiming a
key it never receives: two owners written down, one in fact, and the written-down
one is the one the next reader believes. The card publishes
`AppWindowState.focusedTaskID` instead and the menu acts on that card's
`commandTargets`; Delete lands focus on `BoardFocusMap.card(after:)` itself,
before deleting, because the card can no longer do that for itself. Space is
completion's *other* key and stays the card's, which makes the rule a partition
of one command's `shortcuts` rather than of the enum: the menu takes the key each
item **declares** — `shortcuts.first` — and nothing else.

`BoardKeyboard.command(for:among:)` is the one call a card makes for a press, and
it is where the exclusion lives. It was an `excluding:` argument passed at the
call site, which meant the whole ownership rule was one defaulted argument that
an edit could drop — and the suite was blind to it in both directions: dropping
it gave the card both keys back, and widening the excluded set from "the key the
item declares" to "every key the command names" took Space off the card
altogether. Both left all 488 tests green. `KeyOwnershipTests` is what asks.

**Every surface that draws a card, not the board alone.** The Inbox, each saved
view and the Archive draw the same card through `TaskListView`, and ⌘A, ⌘C, ⌘V, ⎋
and the arrows were dead on all three while the sheet and this file advertised
them without qualification. Those surfaces carry the same vocabulary **less the
four commands that need columns** — `BoardKeyboard.flatCommands` is
`BoardKeyboard.boardCommands` minus `.columnCommands`, derived rather than
written out again, so a key added to one arrives at the other. There is nothing
to move focus across and nowhere to move a card to on a flat list, so ←/→ and
⌥←/→ refuse there; that is the whole of the difference between the two kinds of
surface, and `BoardFocusMap(flat:)` is a single column of rows.

Focus is a `@FocusState` owned by whichever surface is drawing, not state in the
store: it is where the next key press lands, it is not saved, and a second
surface showing the same card would have its own. Moving it also *selects*, so
what the keyboard is on is what the inspector is showing. It is *published* as
`focusedTaskID` for the menu bar, and mirrored back when the menu hands focus on.

`BoardFocusMap` is the rule and `BoardKeyboard.perform(_:on:in:map:today:)` is the
dispatcher, both held apart from the view as plain values so they can be asked
rather than clicked at (`Tests/BoardKeyboardTests.swift`). The dispatcher was a
`private func` on a `View` for most of the phase, where the four behaviours this
section is *about* — ⌥← calling `move`, ⏎ opening the inspector, Space toggling,
focus following a deleted card — could be asked a question by nothing but a
person with a keyboard, and one-line defects in all of them survived the suite.
It returns an `Outcome` of *did the card take the key* and *where the keyboard is
now*: a refusal — ← at the leftmost column — is `isHandled: false`, so the key
goes on to the scroll view and the board still scrolls, and focus stays put. The
map is built from what is **visible**: a card a query has hidden is not one an
arrow key can land on.

**A key brings the board with it; a click brings only as much as it has to.**
A card can be off the bottom of its column or off the right-hand edge of the
board, so arrowing onto one has to scroll it into view — otherwise ← and ↓ walk
the focus somewhere the user cannot see. Clicking cannot be in that position:
the click has already landed on a card that was on screen. The scroll views
watched `focus` itself for most of a phase, which made those the same event, and
clicking a card in the second column slid the board 250pt to centre that column
— the card moving out from under the pointer at the moment it was aimed at.

So the route that moved focus says how far to go, as a `BoardReveal` on
`BoardFocusRelay`, and `BoardScrollView`, `BoardColumnView` and `InboxPanel`
watch that instead:

| manner | who asks | what the board does |
| --- | --- | --- |
| `.centred` | the arrow keys, and the menu handing focus to the neighbour of a card it deleted | puts the column in the middle, so there is board on both sides to carry on arrowing through |
| `.intoView` | a click | shows the column **whole** — the minimum scroll, and none at all when it is whole already |

It is a *raise* rather than a one-shot because two scroll views read every one of
them, the column bringing the card up and the strip bringing its column across,
and a flag either of them cleared would leave the other with nothing. The strip
still ignores a `.centred` reveal that stays in the same column, so ↑ and ↓ do
not re-centre a column that is already on screen under every press — compared
against the *previously revealed card's* column rather than against a remembered
one, which is a value `onChange` hands over and not a second piece of state that
can disagree.

**`scrollTo` has no notion of a margin**, and without one a revealed column
arrives flush against the window's edge with nothing beside it — technically
visible, and reading as still cut off. So a column is scrolled to *wrapped in
`BoardScrollView.revealInset`*, 16pt of padding that the identifier is attached
to, and the wrapper is what has to fit. The wrapper is free: the padding is taken
straight back out of the `HStack`'s spacing and the strip's own margin —
`columnSpacing` and `stripInset`, both of which go negative at this inset — so
the columns sit exactly where they always did, `gutter` apart and `stripPadding`
from the ends. The wrappers overlap each other by twice the inset, which is empty
space either way and hit-tests as nothing.

Focus moved by anything else — Tab under Full Keyboard Access, a VoiceOver cursor
— scrolls only as far as the system scrolls it, which for VoiceOver is all the
way and for Tab is nothing on this board.

**The panel is the other thing that can take a card off the screen, and it does
it without moving the card.** The inspector opens *beside* the board and takes
its width out of the board's, so a card picked at the right-hand edge is behind
the panel by the time the panel is there: selected, its own detail on screen, and
the card itself gone. The reveal the click raises cannot answer that one — it is
measured while the board is still whole, and the minimum scroll that makes a
column whole in a board about to lose a third of itself is no scroll at all. So
`BoardScrollView` asks for the same `.intoView` again when `isInspectorOpen` goes
true, **after `panelTravel`**, and the wait is the part that cannot be read off
the source. Measured on the desk in a 1240pt window with the panel closed and the
card at x=1234–1486: a scroll issued as the panel opens left the card exactly
there, and so did one issued a runloop turn later. The layout reports the board's
new 672pt immediately, but the scroll view's own visible rect follows the panel's
animation rather than jumping to the end of it, so a scroll taken then is
measured against a board that is still moving. The same measurement taken after
`panelTravel` put the card at x=1034–1286, clear of a panel arriving at x=1312.
Only on the way *open* — closing the panel hands the width back, and a column
whole in the narrow board is whole in the wide one. And nothing moves on an iPad
narrow enough that the panel is drawn *over* the board instead: the board keeps
its width, so the minimum scroll is none, which is the honest answer when there
is nowhere else to put the card.

`BoardRevealTests` pins the wiring and the arithmetic; `UITests/InspectorRevealTests`
is the one place the pixels are asserted rather than measured by hand, because the
iPad is the surface a test can drive: it taps the rightmost card the board is
showing whole, insists that card *was* behind the panel — a run on an iPad wide
enough that nothing was covered proves nothing — and waits for it to come clear,
with a second case on a card at the far left that must not move the board at all.
Nothing can pin the desk's pixels, because `scrollTo` goes to a `ScrollViewProxy`
that keeps no record of having been called. The behaviour was measured against the built app through the
accessibility API instead — `AXPress` on a card and a key posted to the process,
neither of which touches the host's pointer or keyboard. In a 372pt board with
272pt columns: a click on a column already whole moved it 0pt, a click on one
clipped at either edge left it exactly 16pt from the edge it came in past, and
→ left the next column centred to the point.

The focus ring is a 1.5pt ring set 3pt *inside* the 2pt selection ring rather
than a second colour, so a card wearing both reads as both, and the difference is
geometry rather than hue under `.accessibilityDifferentiateWithoutColor`. Both
differ, not one of them: either difference alone is one literal away from being
tidied out. The four numbers are `Ring` values rather than literals in an
overlay, because a constant nothing can reach is a constant no test can defend —
and they are on **`Metrics`**, as `selectionRing` and `focusRing`, rather than
statics on `Ring`. A ring follows the corner it is drawn on: the pad's card is
rounded at 14 and the desk's at 12, so one pair of statics fitted to the desk
drew the iPad's selection ring 2pt inside its own edge. `FocusRingTests` asks
both presets, and asks the radius to match the card it is drawn on.

**The inner ring is drawn only where it says something the outer one cannot** —
`BoardTaskCard.drawsFocusRing(isFocused:isSelected:selectionCount:)`. Once the
selection follows the keyboard onto whatever card it lands on (below), the
ordinary picked card is both selected *and* focused, and a ring inside a ring was
one border drawn twice. Two states are left where the pair are not the same fact,
and both keep it: a focused card **inside a multi-selection**, which is the one
the arrows move from and ⇧ sweeps from while every card in the selection wears
the outer ring alike; and a focused card **not selected at all**, which is where
a ⌘-click taking a card out of the selection leaves it — without the inner ring
the card holding the keyboard would carry no mark whatsoever.

And **the card has to be told whether it has the keyboard**. Asking from inside
answers `false` either way: `\.isFocused` is false there because the element
AppKit ends up focusing is the card's own `Button` rather than the `focusable()`
wrapper around it, and a `FocusState.Binding` held as a plain stored property is
not a dynamic property, so reading it hands back whatever was true when the
binding was made. The card sat on both for the whole phase and drew no focus ring
at all, on any surface, while every test of the ring's geometry passed. The
wrapper that holds the binding *as* `@FocusState.Binding` is the one place that
can answer, and it passes `isFocused: Bool` down.

**The selection follows the keyboard onto a card, however focus got there.** Two
rings only read as one state when they move together, and they did not: the
selection moved in the card's `Button` action, which fires on mouse *up*, while
AppKit moves the first responder through the responder chain on mouse *down*.
Every click therefore had a window — as long as the mouse was held — with the
focus ring on the card being pressed and the selection ring still on the last
one. A **drag** never completes that action at all, so the two never came back
together: the card being carried wore the inner ring and the card left behind
wore the outer, until some later click happened to land. The rule the arrows
already kept — every focus move selects what it lands on, because what the
keyboard is on is what the inspector is showing — is now stated once, as
`BoardKeyboard.selectionFollows(focusOnto:selection:held:)`, and applied wherever
focus arrives. It declines in the two cases where the user is working *with* a
selection rather than moving through one: a held ⌘ or ⇧ means "as well as what is
already picked", so collapsing onto the pressed card on mouse down would throw
that away before the click meaning to add to it had been delivered; and a card
already in the selection is the same judgement from the other side, since
arrowing into a multi-selection or picking one of its cards up to drag is not a
decision to drop the rest.

**Every one of those actions is also an `.accessibilityAction(named:)` on the
card** — complete or reopen, archive or restore, delete, Move to Inbox, and one
"Move to <column>" per column of the card's *own* board, which is not always the
board on screen. Until now the only way to move a card was a pointer dragging it,
which is no way at all with VoiceOver or Switch Control; ⌥←/→ and the rotor are
the same command reached two ways. A card in the Inbox is on no board and so has
no columns to name: its route is the context menu's board destinations, which is
not a rotor action, and closing that is 7.1's.

**The rotor acts on the same cards the keys and the menu do** —
`store.commandTargets(task.id)`, so the whole selection when the card is part of
it. Complete, delete, archive and each "Move to \<column\>" moved exactly one card
while the identically named menu item took all three, which is a worse lie to an
assistive user than to a sighted one: the action's name is the only description
of what it is about to do, and there is no board to watch not change. The tick
and the context menu stay singular on purpose — a pointer is aimed at one card.

### The clipboard

⌘C and ⌘V are the *standard* Edit items, made live on a focused card by
`copyable` / `pasteDestination` rather than declared as items of the app's own —
an app-declared Copy takes ⌘C away from every text field in the window. A copy
carries `TaskTransfer`, which is the drag payload: the board's own type *and* the
plain text `NW-118 Drag-and-drop between columns`, so one ⌘C pastes back as a
card here and as a line into a commit message. Copying with several cards
selected copies all of them, in board order.

⌘V makes a card per line of the pasted text where the focused card lives, so a
list pasted out of a note arrives as a list — and **the whole paste is one undo
step**, because one act of the user's is one ⌘Z. `store.addTasks(to:titles:)` is
what makes it one: looping `addTask` gave three pasted lines three ⌘Z's, and
looping it *inside* an `undoable` would have been worse, because the selection
change that ends a surface's open editing sessions would then land inside the
bulk step, where `registerUndo` bails, and the user's half-typed title would fold
into the paste. The session state moves once, after the step closes.

**Copy Link** is a separate verb on both cards' context menus and puts
`simplekanban://task/<uuid>` on the pasteboard. It is not a second
representation on the ⌘C payload: that copy is *the card*, meant to paste back as
a card or as a line of prose, while the link is a reference to a card that stays
here. See **System integration** for what happens when one is opened.

A leading task code is stripped: text copied out of this app comes back with one,
and a new card carrying another card's code in its title would be lying about
which task it is. **A task code has a letter in it** — `NW-118`, `IN-147`,
`AL-140`. Digits-dash-digits is a date, and `2024-01 Review the quarter` used to
arrive as `Review the quarter` with its date silently eaten. An **archived card
is not a paste destination**: its placement is the column it left, so the cards
would appear on a board the user is not looking at.

### The shortcuts sheet

Help ▸ Keyboard Shortcuts (⌘/) opens `ShortcutsSheet`, on either platform. Seed task `t12`, in the
Done column, has been called "Keyboard shortcuts sheet" since the first commit;
the sample data claimed this shipped long before it did.

Every row is read out of `AppCommand`, so the sheet cannot claim a key the app
does not have. It is a partition of the vocabulary: commands **with** a key are
rows under their group's heading, including the `.board` group that has no menu
and the system's Undo and Redo that the menu deliberately does not declare;
commands with no key are named in a footnote ("In the menus, without a key: …");
and the unbuilt ones in a second ("Not built yet: …") — empty since Import… and
Export… were built, and the sentence disappears with it. Both footnotes are
filtered out of the same list rather than written out, so a command that gains a
shortcut leaves its sentence on its own. `AppKey` exists for this sheet:
`KeyEquivalent.leftArrow` is U+F702 and renders as nothing at all, so every key
carries a glyph a person can read.

The sheet is macOS-only: it is drawn from the menu bar's vocabulary, and only a
window has one. The phone has no hardware keyboard to teach. The iPad's cards
carry the same key handling as the desk's — they draw the same `BoardCard` — but
nothing on iPad advertises it yet.

## The macOS window

The scene is `Window`, not `WindowGroup`. Every piece of per-window state this
app has — the selection, the surface, the inspector, the open composer — lives in
the one shared `BoardStore`, so a second window would not be a second view of the
board but a mirror of the first, scrolling and selecting in lockstep. Making two
windows genuinely independent means lifting that state out of the store, which is
a larger change than a parity pass. One window also takes New Window off the File
menu, which is where ⌘N's ambiguity started.

The frame is still restored: AppKit autosaves it against the scene's id, and
`.defaultSize` only applies to a window it has never seen.
`.windowResizability(.contentMinSize)` takes the floor from the content, which is
what lets it drop from 940pt to 708pt when the sidebar is hidden — pinning
`.contentSize` instead would also pin the *maximum*, and a board is a surface
people want as wide as the screen.

`MacRootView` re-injects an `AppWindowState` of its own when the environment has
none — as `PadRootView` now does too — so the view still stands up in a preview or a test host. It also owns the
`BoardFocusRelay` the shared board publishes its keyboard focus through, and
mirrors it onto the window state both ways — the board is `Sources/Shared` and
cannot name a window, and the menu bar hands focus on as well as reading it. It
carries File ▸ Import…/Export…'s panels for the same reason: the menu bar is
outside every window's view tree and the panels have to be presented from inside
one.

### The header is the title bar

`.windowStyle(.hiddenTitleBar)` hides the title bar; it does not give back the
32pt it occupied. SwiftUI keeps that band out of the safe area, so the board
header was laid out *below* it and read as a second strip of chrome under the
traffic lights — the title, the search field and the buttons all a row lower than
the window controls beside them. `MacRootView` takes the band back with
`.ignoresSafeArea(.container, edges: .top)`, which puts the header against the
top of the window where the title bar used to be.

That leaves the lights. AppKit sits them near the top of its own 32pt bar, which
is not the centre of a 50pt header, so `windowButtons(centredAt:)` moves them
onto the header's row — measured, not assumed: `MacRootView` reads the height the
bar actually laid out at, because chrome grows with the type inside it.

Two things about that placement are load-bearing.

**A light hanging out of the title bar refuses the click.** `NSView.hitTest`
stops at a view's own bounds before it ever asks a subview, so a button pushed
below the 32pt bar draws exactly where it was asked to and then does nothing.
The header's 50pt is the tallest row whose centre a 14pt light can still reach
from inside that bar, which is where the number comes from, and the aligner
clamps anyway.

**AppKit puts them back.** A resize is enough. Each button is watched for the
move rather than placed once — but correcting one the moment it moves is still
not enough, because AppKit is mid-layout when the notification arrives and writes
the zoom button's frame once more on the way out. Measured: close and minimise
held their row across a resize and zoom alone snapped back up. So every
notification also books a second pass for the next turn of the run loop. Full
screen is left alone entirely; the lights come down there in an overlay that has
nothing to do with this window's header.

The sidebar reserves the band the lights sit in — 14pt above, 16 for the lights,
20 below — which comes to the header's own 50pt, so the first row of the source
list starts level with the seam under the header beside it. With the sidebar
hidden there is nothing to hold that gap, and the toolbar takes a 68pt leading
inset instead.

**The desk's header carries no capture button, and the iPad's does.** A labelled
**New task** sat at the right of this row on both platforms until 8.2. The desk's
went and did not come back: the foot of its source list already has a capture
button, ⌘N is on the File menu, the menu-bar extra takes one from anywhere, and
every column has a `+` in its heading and a dashed add row under its last card —
six ways to make a card, one of them in the narrowest row in the window.

The iPad kept one, because it has no menu bar and therefore no ⌘N: without it the
only ways to make a card there are a column heading's `+` and the Inbox panel's,
both of which decide where the card goes before you have decided what it is. And
**it captures to the Inbox**, which is the whole of that sentence — it used to
open the composer on the board behind it, which is the column heading's job. The
three ever-present `+`s now say one thing on all three platforms: the source
list's foot on the desk (`captureToInbox()`), this one
(`beginCapturingInInbox()`), and the phone's over the tab bar (`quickCapture()`)
all land a card in the Inbox, because a capture is what you write down before
you know where it goes. A column's own `+` adds to that column of that board,
where the destination is the part that is already settled. But
it is **a circle with a `+` in it now, and no word** — the same control the
phone floats over its tab bar, at the 44pt square every other control in this
row claims. The label was 117pt of a row whose only compressible piece is the board's
name; the glyph is 44. That is 73 points back to the name and a fold line 73
points lower, and the word it dropped is carried by the accessibility label, which
is what a reader was getting either way.

`BoardToolbar.Metrics.capture` is how the two presets differ — a diameter on the
iPad and `nil` on the desk, in the shape `ColumnEditorMetrics.arrowEdge` uses,
rather than an `#if os()` in a shared body (C1).

There are two more scenes beside it. `Settings { }` is a root of its own and
inherits nothing from the window, so the palette, the tint and the appearance
override are all resolved again in `SettingsWindow`. `MenuBarQuickAdd` is a
`MenuBarExtra` — a title field, a destination picker that remembers its choice,
and "Open Board" — so a capture can be made without bringing the app forward.

## The iPad

`TARGETED_DEVICE_FAMILY` has said `1,2` since the first commit and the plist has
granted the iPad all four orientations, but `RootView` picked its surface with a
bare `#if os(macOS) … #else PhoneRootView()`, so **an iPad ran the phone layout
stretched across a 13" display**: one column at a time, a floating tab bar, a
drawer instead of a sidebar.

**The layout is chosen by the idiom *and* the size class, not by OS and not by
either one alone.** `RootSurface.resolve(idiom:horizontalSizeClass:)` in
`SimpleKanbanApp.swift` is the whole decision, and each half answers a different
question: the **idiom** says which device this is, the **horizontal size class**
says how much of it this window has. `.pad` needs both.

The size class alone is not the iPad, and shipping it as if it were handed the
desk's three panes to a phone. A Max- or Plus-class iPhone reports a *regular*
horizontal size class in landscape, so an iPhone 17 Pro Max at 956×440 drew
`PadRootView` — the split view's sidebar toggle, the inspector, the board's
column controls — and never drew the three-up landscape board `PhoneRootView`
lays out for exactly the devices that have room for it (**Landscape**, below). The
idiom alone is not the window either: an iPad in Slide Over or a narrow split has
a phone's width and nowhere to put a sidebar, which is why the size class keeps
its half of the say. `RootSurfaceTests` walks the four combinations.

**The iPad gets the desk's surface, and it is the same code.** The point of the
item was to end up with fewer implementations of the board, not three, so the
board machinery moved out of `Sources/Mac/` into `Sources/Shared/` and both roots
compose it:

| shared view | was | drawn by |
| --- | --- | --- |
| `BoardScrollView` | `MacBoardView` | `MacRootView`, `PadRootView` |
| `BoardColumnView`, `BoardColumnEditor`, `AddColumnTile` | `MacColumnView` | `BoardScrollView` |
| `BoardTaskCard`, `BoardCard`, `ListCard` | `MacTaskCard`, `MacBoardCard`, `MacListCard` | the board, the flat lists, `PlatformTaskCard` |
| `BoardTaskComposer` | `MacTaskComposer` | columns, the Inbox |
| `BoardSidebar` | `MacSidebar` | `MacRootView`, `PadRootView`'s split view |
| `BoardToolbar` | `MacToolbar` | both roots |
| `TaskInspector` | `MacInspector` | `MacRootView`, `PadRootView`'s inspector column |
| `BoardFocusMap`, `BoardKeyboard`, `CardKeyboard` | `MacBoardFocus.swift` | every card |

**The source list has two ways out on the iPad**: the toolbar's toggle, which is
the button either orientation needs, and a pull from the leading edge, which is
the gesture the shape suggests. See **The edge swipe** — including why the split
view did not bring the second one with it.

Each carries a nested `struct Metrics` with a `.desk` preset and a `.pad` one, and
**nothing in them branches on `#if os()` to pick a size** (C1). The `.desk`
presets are the numbers that were literals in `Sources/Mac` an hour before, so
macOS renders what it rendered. `.pad` is the same drawing at touch sizes: 320pt
columns instead of 272, 44pt header buttons instead of 22, the 44pt
`CompletionToggle.Metrics.sheet` tick instead of the 26pt one, and the `.sheet`
preset of every control the inspector already shared with the phone. Measured on
a booted iPad Pro with `XCUIElement.frame`, every hittable button, text field and
search field on the board, the Inbox and a saved view is at least 44×44pt.

Two of those presets are about *placement* rather than size. `ColumnEditorMetrics.arrowEdge`
is the side the Edit Column popover hangs off: the desk names `.bottom`, because
a window has room on every side of a column header; the iPad names **none** and
lets UIKit choose. A column header sits 134pt from the top of a display, and a
popover pinned above it opened off the screen — the Name field measured at
y = −4.5 and every colour swatch reported `hittable=false`. And `TaskColumnMetrics.pad`
is the saved views' preset, which lived as a private `TaskListMetrics` constant
inside `PadRootView` until it was pointed out that a preset a view keeps to
itself is one no test can enumerate — and which became the *board's* column when
the views wrapped into columns.

**The container is a `NavigationSplitView`**, so slide-over, Stage Manager and
the sidebar's own show/hide behaviour arrive with it rather than being rebuilt;
the phone's drawer is an overlay and a different thing. The detail column hides
the navigation bar and draws `BoardToolbar` instead, which is why the bar carries
a sidebar button on iPad and not on macOS: the menu bar owns that verb on the
desk, and `toggleSidebar` is `nil` there.

**The inspector is laid out, not presented.** It was `.inspector(isPresented:)`
on the detail column, which drew the panel over the *whole* column — the toolbar
included. In portrait with the source list out, the toolbar's **New task** button —
which the bar carried then — measured 117×44 at x=839 inside a 1032pt window and
reported `hittable=false`: the
surface's primary action was unreachable in one of the two orientations, and a
card reorder dragged inside Backlog, hundreds of points from where the panel was
drawn, silently did nothing. `PadRootView.detail` is now the toolbar above an
`HStack` of the board and the panel — the same three pieces `MacRootView` puts in
the same order — bound to the same `store.isInspectorOpen` the desk toggles, and
holding its 384pt column with nothing selected exactly as `MacEmptyInspector`
does. A sibling cannot cover the toolbar. Re-measured after the change, New task
is `hittable=true` with the list out and with it hidden, and the reorder lands.

The panel is in the same competition as the two that open on the left: all three
are a column wide, and a window that cannot hold what is open closes whichever
was not just asked for, furthest from it first. See **The three panels take
turns**.

Where there is not room for both the board and the *inspector*, the inspector goes
**over the board** — never over the toolbar, which is the whole point. `PadRootView` measures the row with
`onGeometryChange` and insets the panel only while a `.pad` column and its
margins would still fit beside it; below that it is a trailing overlay. An iPad
mini in portrait with the source list out leaves 130pt of detail beside a 384pt
panel, and 130pt is half a column.

### A card made here opens in the editor

**On the iPad, and only there**, committing a composer opens the inspector on
the card that was just made — `BoardStore.commitDraft`, guarded by
`BoardStore.isPad`. `addTask` had already selected it; what was missing was
somewhere to see it.

The other two platforms deliberately do not, and the difference is real rather
than a preference:

- **The iPad's editor is a panel the *app* puts away.** Three panels compete for
  one window and `PadRootView` closes whichever is furthest from what was last
  asked for, so a card can perfectly well be made into an editor that is not on
  screen — selected, and nowhere to be seen.
- **The desk's is a panel the *user* puts away.** Its window holds all three
  columns at nearly any size, so an inspector that is shut is one somebody shut
  on purpose, and re-opening it on every card made would be overruling that a
  dozen times an afternoon.
- **The phone has its own answer already**: a card made from the `+` over the
  tab bar opens in a sheet, and one made from a column's composer deliberately
  does not — you are filling in a list, and a full-screen sheet between every
  two cards would bury it.

`BoardStoreMutationTests` states it as "matches the platform" rather than as two
tests behind an `#if`, because the claim is exactly that the rule reads the
platform: a build where the branch was deleted passes one half and fails the
other whichever destination the suite is run on.

### The home indicator's strip is not a margin

iPadOS keeps about 20pt along the bottom of the screen for the home indicator,
and every pane laid out inside that inset stops short of the glass by that much.
It reads as a gap somebody chose rather than as a system margin, and it is not
symmetric with anything: the board's strip of columns clears the toolbar by
`stripPadding` at the head and the bottom of the window by `stripPadding` **plus
20** at the foot — 16 and 36 — and a saved view was worse still, a 28pt foot
against a 12pt head with the strip under that as well.

`HomeIndicatorFoot` — `.underTheHomeIndicator()` — is the one place the answer is
written down: a `GeometryReader` reads the inset off the proxy, because how much
room the indicator wants is the device's answer rather than a number to type, and
a **negative bottom padding** hands the pane that much more than its slot.
`ignoresSafeArea(.container, edges: .bottom)` does not do it and was measured not
doing it: inside a `NavigationSplitView` the inset is a layout margin UIKit has
already applied to the column, so a colour in a `background` can be *drawn* over
it — which is what the Inbox panel and the task editor do — while a frame cannot
reclaim it. A negative padding is plain layout and owes the safe area nothing.

Four panes take the strip: the source list, the board's column strip, a saved
view, and — through the same modifier — nothing else. It is safe for them because
the indicator is a short pill in the middle of the bottom edge that takes no
touches; only an upward swipe from the very edge belongs to the system. It is
**not** for a control that has to be pressed down there, which would sit under
the pill and read as unfinished, and the `TaskColumnMetrics.pad` foot was
brought back to the head's 12 at the same time so the two edges read as one
margin.

Measured on a 13" simulator: the columns' fill ends 32px — 16pt at 2× — above the
glass, which is exactly the 16pt above them.

### The header folds when its column runs out of width

The bar is a fixed-width search field, a capture button and three toggles, and
none of them gives ground — the only thing in it that can be squeezed is the
board's name. So a
narrow detail column squeezes the name and nothing else, and the name is the one
thing in that row you cannot look up somewhere else. Measured on a 13" iPad in
portrait with the Inbox panel open, back when the row also carried New task: the
bar laid out at 712pt and drew "Northwind iOS 3.0" as **"Northwind i…"** in 131
of them, beside an empty 220pt field.

**Below 700pt the field folds into a magnifying-glass button**, and the name gets
those 220 points back — the same board draws its full title with room over. (The
line was 773 while capture was a labelled New task button; drawing it as a circle
gave the bar back 73pt, so on a 13" the source list and the Inbox panel now have
to be out *together* before it folds. With only the panel out that bar clears the
line by twelve points, which `Tests/ToolbarFoldTests` states rather than hides.)
Pressing the button drops the field into a row of its own under the bar, focused,
with the keyboard already up: it was folded away *from* a field, so arriving at
anything else would cost the reader a press and then a hunt for the field's own
22pt band of text. It is the same field either way (`searchField(fills:)`) rather
than a second copy, since a second copy is a second place for the clear button,
the hit area and the ⌘F token to drift out of step.

**A row rather than an overlay**, which is the tempting spelling: an overlay hangs
over the top of the board, and the top of the board is where the cards a live
search has just matched are. The bar grows for as long as the field is up and the
board starts lower.

Three things follow from the field being the only place this surface shows the
query:

- **A live query keeps its field.** A window dragged narrow around a search folds
  the bar, and `showsSearchRow` is the flag *or* a non-empty query — otherwise the
  board would sit there filtered with nothing on screen saying so. The button is
  outlined in the accent while a query is running, for the same reason.
- **Putting the row away is a cancel**, query and all. Leaving the query behind
  would hide the filter and its only undo in one press.
- **A row that appeared on its own does not take the keyboard.** `focusWhenReady`
  is conditioned on the flag, not on the row: a resize that raises a keyboard is a
  resize typing into a text field.

`Metrics.searchFits(barWidth:…)` is the decision, and it is an *estimate* — it has
to be. Measuring the squeeze means measuring the bar with the field in it, and
taking the field out on the strength of that measurement gives the name room,
which puts the field back, which squeezes the name: it would oscillate at exactly
the width it matters at. So the one control that sizes to its own content — the
Inbox toggle, whose badge is a number that grows — carries its measured width in
the preset, and `titleFloor` — 160pt, about fourteen
characters of the pad's 26pt serif — is the line. `Tests/ToolbarFoldTests` pins
the arithmetic, including that the fold happens *before* the row overflows rather
than after, and that it is monotonic in width so no drag can make it flicker.
`UITests/ToolbarFoldTests` is the half only a live layout can answer, and
`UITests/PadCaptureTests` is the capture button's: a `+` with no word publishes
as a button with an empty name unless something gives it one, and a missing
`accessibilityLabel` changes nothing on screen — so the test presses the button
the header's row carries and checks it reaches a composer, and that the composer
is the Inbox panel's rather than the board's.

**The desk does not fold, and not because its windows are wide.** Its bar *is* the
title bar: the traffic lights are moved onto the row it lays out at and
`MacRootView` measures the bar to find that row, so a second row under it would
take the lights down with it — see **The header is the title bar**. What keeps the
desk's bar in one piece instead is `MacRootView.floor`, the window's own minimum,
which the same test checks still holds everything in the row. `Metrics.foldsSearch`
is how the two presets differ, rather than an `#if os()` inside a shared view.

What the iPad does *not* take from the phone: the tab bar, the column chips and
their paging, the drawer and the detail sheet. Its cards are `BoardTaskCard`, so a tap selects and
fills the inspector rather than raising a sheet, and `store.sheetID` is never set.
The Inbox panel is `TaskListView` under a heading and the saved views are
`TaskColumnsView` — see **The views wrap into columns** — and neither carries a
"← Board" button, because every destination is a row in the sidebar, which is the
whole reason the iPad has a split view and the phone has a drawer.

Two things are knowingly left behind. **⌘C and ⌘V are macOS-only**: `copyable`
and `pasteDestination` are macOS 13 but iOS **27**, and this app deploys to iOS
26, so `CardPasteboard` puts them behind an availability check and an iPad on 26
keeps every other key on the card. `onDragSessionUpdated` is the same story
(macOS 26, iOS 27), so on iOS 26 a lifted card does not dim while it is in the
air — the drop handlers still clear the highlight.

**Every menu-bar key is the card's on iPad.** `BoardKeyboard.menuOwnedShortcuts`
is the set a card must *not* claim, because a menu key equivalent is dispatched
before the responder chain sees the event — and that is a fact about AppKit. The
set was built on both platforms from `AppCommand.isMenuItem`, but `BoardCommands`
is only ever built into the macOS scene: the iPad's `WindowGroup` declares no
commands, so nothing took those presses first and excluding them left ⌘⌫ and ⌘⏎
handled by nobody at all. It is `#if os(macOS)` now, and empty elsewhere. The
other six the menu declares are in no card's vocabulary either way.

## Drag and drop

A card in flight carries `TaskTransfer` — its id, title and code — under the
app's own exported type, `com.n14395.SimpleKanban.task`, declared in
`project.yml` under `UTExportedTypeDeclarations` because a type the bundle does
not declare is registered dynamically and resolves to one that conforms to
nothing. The payload used to be the id as a bare `String`, which meant a column
lit up for a URL dragged out of Safari, or for any word dragged out of a text
field, and then had to decide at drop time that it had not meant it. The
plain-text representation — `NW-118 Drag-and-drop between columns` — is what a
card dropped into a text editor leaves behind, and is what ⌘C will put on the
pasteboard. Checklist rows have their own, `SubtaskTransfer`, which carries the
task it came from so a row cannot land in the other surface's checklist for a
different task. **Columns have a third**, `ColumnTransfer`, under
`com.n14395.SimpleKanban.column`, and it carries the *board* for the same
reason: `moveColumn` is defined over the active board, and a second macOS window
can be showing another one.

### Re-ordering the columns

**The columns are re-ordered from a menu and from the settings sheet, and no
longer by dragging one across the board.** *Move Left* / *Move Right* on the
column's own menu — and on the phone's column chip — move one column one place;
**Board Settings…** on the same menu opens the whole order as a list, with that
column already unfolded in it, where a row can be dragged up and down and the
arrows beside it do the same thing without a gesture. `BoardStore.moveColumn` is
what all of those call.

**The board's header was a grip and is not one now.** A column header is a run of
text inside a horizontal `ScrollView` full of cards, which is three gestures
wanting the same touch: the board's pan, a card's own lift, and the column's. The
grip was written to win that fight — the name alone lost the touch to the
scroller every single time, measured on an iPad Air, so the grip had to grow to
the header's full width — and a control that has to be that greedy to work at all
is a control aimed at by accident. Pressing a column to read its name should not
be able to move it. The list in the settings sheet is a vertical list of rows,
where a drag means one thing, and it is drawn beside the arrows that say the same
thing to VoiceOver and Switch Control, to whom a lift is invisible (7.1).

**The drop is `BoardStore.dropColumn(_:at:)`**, which takes a `ColumnTransfer`
and a `ColumnCaret` and inserts into the gap the caret names. It replaced
`dropColumn(_:onto:)` for the reason `drop(_:at:)` replaced the cards'
`move(_:onto:)`: a drop that names a row can only be resolved by the direction of
travel, which is unguessable from outside and leaves the head of a list
unreachable. `move(fromOffsets:toOffset:)` counts in the pre-move array
everywhere in this app, so `.above` is the anchor's own index and `.below` is one
past it. Dropping against itself, into either gap it already sits between, onto a
board it is not on, after Done, or naming a column the board no longer has are
all refused rather than resolved to whatever `firstIndex` returns.
`dropOffset(from:to:)` stays on the store for `ChecklistView`, which is the last
caller that still resolves a row into a gap.

`ColumnReorderTests` pins that half — both directions, because the off-by-one
only shows in one of them — and one case in it reads `BoardColumnView`'s own
source to say the board's strip carries no `ColumnTransfer` and nothing on it is
`draggable`. That is the shape the claim has to take: `dropColumn` answers the
same whether or not anything on screen is wired to it, and a UI test that drags a
header and asserts nothing moved passes just as readily when the drag was simply
lost to the scroller. `UITests/ColumnDragTests`, which pressed the strip's grip,
is gone with it.

**The wiring is what a real drag is for, and the sheet's has one.**
`BoardSettingsSheetTests` presses a row, drags it to the *top* of another and
holds — the one aim the two rules disagree about, and the one the report that
started this described. It asserts the dragged column landed between the row
above that gap and the row under it; the old rule satisfies every other line in
the case and fails that one, measured by putting it back. It also re-seeds the
simulator first, because it reads positions and a second run would otherwise
measure what the first one left.

Dragging is off wherever the cards on screen are not in the board's own order —
`BoardStore.allowsCardDrag`, which is `activeView == nil && sortOrder == .manual`.
A drop resolves against the `tasks` array, because "put this card before that
one" is an index in it, so it only means what it looks like where the cards on
screen *are* that array. **In a saved view** they are not: the list draws no
columns at all, and Recently updated and the Archive sort by their own
timestamps, so a drop would move the card into a column that is nowhere on
screen, at a position bearing no relation to the row it was aimed at — silently,
and to an archived card as readily as a live one.

**A query used to be the other reason, and is not any more.** While the board was
drawn from the search's answer it had to be: the cards in between were hidden, so
a card dropped between two of the few left lands somewhere nobody can see and
moves again when the query clears. The search is a panel over the board now — see
**Search** — the rows underneath are untouched, and a card the reader can see is
a card they can move. The tooltip lost its second sentence with it; there is one
reason left to name. `SearchScopingTests` pins the rule.

**Every drag has a way to say the same thing without one.** A long-press lift is
unreachable to VoiceOver and to Switch Control, so a capability that exists only
as a drag does not exist for either — and reordering was exactly that on the
board and in the checklist. Three menus close it:

| what was drag-only | the menu it is on now |
| --- | --- |
| a column's place in the board | **Move Left** / **Move Right** on the column's own menu, and the list in **Board Settings…** — the drag on the board is gone |
| a card's column | **Move Column ▸**, drawn by `ColumnDestinationItems`, and one rotor action per column |
| a card's board, or the Inbox | **Move Board ▸**, drawn by `BoardDestinationItems` |
| a sub-task's place in the list | **Move Up** / **Move Down** on the checklist row's context menu |

**A card's place *within* a column is the drag's alone.** Move Up / Move Down
were on both card menus and are gone. They named a **neighbour** rather than a
place, which is the one filing verb in the app that does: everything else — the
board menu, the column menu, the rotor actions, ⌥←/→ — says where the card should
end up. They also could not be said straight. `move` refuses a `before: nil` into
the place a card already is (that is what stops a drop on a column sending a card
to the bottom of its own), so **Move Down** was spelled backwards as *the card
below moves above this one*, and the last row of a column was therefore not a
destination at all — the menu drew one item there, two in the middle and one at
the top, changing shape as the card travelled. `CardDropTests` still pins the
arithmetic, because the drop caret's `before:` is the same call.

**Move Board and Move Column are the two halves of one question**, and they split
where `BoardDestinationMenu` and `MoveToPicker` split it on the detail surfaces:
which board, then where on it. Both draw the card's *own* board's columns rather
than the board on screen — `BoardStore.moveDestinations(for:)` is that rule, and
the rotor actions read it too, so the list a pointer sees and the list VoiceOver
is offered cannot drift. A tick marks where the card is now and picking it does
nothing; a card in the Inbox or the Archive has no columns, and **Move Column** is
then not drawn rather than drawn empty. The checklist's two items go through
`dropOffset(from:to:)` — the drop closure's own arithmetic — so the one menu that
still says *up* and *down* cannot end up with a second idea of where a row lands.

**The macOS sidebar rows are drop destinations too.** A card dropped on a board
row is filed onto that board's landing column — the first column work can start
in, not its Done — and a card dropped on the Inbox row is unfiled. Both are gated
on the same `allowsCardDrag`. It is the only pointer route back to the Inbox now
that the Inbox is not a column, which is why it exists; the keyboard-and-menu
routes are in **Boards, columns and the Inbox**.

**A lift ends when the payload lands, not when the mouse comes up.** A card in
flight is drawn at 40% — `BoardStore.draggingID`, kept by `CardDragSession` off
`onDragSessionUpdated` — and a drop on macOS is not one moment but four: the
mouse comes up, the drag image goes, the session reports `ended`, and *then*
SwiftUI finishes loading the payload off the pasteboard and calls the
`dropDestination` handler that moves the card. The last two are around a tenth
of a second apart. Undimming at `ended` therefore drew the card back at full
strength **in the column it was leaving**, where it sat until the move landed —
a card flashing back to where it came from, which is what a drag is supposed to
look like when it *fails*. So `ended` now only ends the lift for an operation
that carries nothing — the drop refused, the drop nowhere, the drag to the
Trash, all of which are the end of it — and everything else waits for
`dataTransferCompleted`, the phase that fires on the same beat as the handler.
In the ordinary case `performMove` gets there first: it moves the card and ends
the lift in one mutation, so the two can never be a frame apart. Every route
goes through `BoardStore.endDrag()` for that reason, and `DragLiftTests` pins
both halves — the store's, by calling it, and the view's, by reading which phase
the source listens to, since a drag session cannot be started from a test.

### The card in the air says where it is going

A lifted card dimmed and the column under the pointer lit up, and that was the
whole of the feedback. It answers **which list** and says nothing about **where
in it** — which is the entire content of a reorder. Worse, the answer is not the
one anybody would guess: `before:` can only spell "ahead of that one", so a card
dropped onto a card *below* it lands **after** that card, and one dropped onto a
card *above* it lands **before**. The same target, two different results,
depending on which way you came.

**And the rule itself had to go.** Reading the side off the direction of travel
is the only thing "dropped onto this card" *can* mean, and it cannot name the top
of a list: a card dragged from anywhere earlier in board order onto the first
card of a later column landed after it, so no gesture on the board put a card at
the head of another column. The caret, drawing that faithfully, kept appearing on
the far side of the card the pointer was on.

So a caret names a **gap**, and each card offers its two halves as separate drop
targets — `BoardTaskCard.dropZones`. The top half means *above this card*, the
bottom half *below it*, and `BoardStore.drop(_:at:)` inserts into exactly that
gap: `before:` the card for the top half, before whatever follows it *in that
list* for the bottom, appending when nothing does. Nothing is inferred, so
`move(_:onto:)` is no longer what a board card calls. A drop into the gap the
card already occupies is a no-op that registers no step — a ⌘Z that takes back a
card which never moved is worse than no ⌘Z at all.

`dropTargetCaret` joins `dropTargetColumnID` and `isInboxDropTarget` on the
store, cleared by `endDrag` with them, and set by whichever half the pointer is
in with the same clear-only-if-it-is-still-mine guard the checklist rows use:
leaving one for the next fires this one's `false` *after* the other's `true`. The
card named draws a 3pt accent capsule on the edge named — the mark
`ChecklistView` already draws between its rows, a shade thicker because a
column's gaps are wider than a checklist's.

Two things about those zones are load-bearing and were both found by measuring.
They are **over** the card, not behind it: a drop stops at what it lands on, and
with the zones in the background a drag released on a card landed nowhere. And
they exist **only while something is in the air**, because they are plain
hit-testable views and over an idle card they would take the click that opens it
— during a drag there is no click to take. They reach half the column's
`cardSpacing` past each end, so one card's halves meet the next card's in the
middle of the gap and a pointer between two cards is over one of them rather than
over neither, which is what made the caret blink out and jump to the foot of the
column.

**The iPad had no caret at all**, and the reason was upstream of the caret.
`onDragSessionUpdated` — what `CardDragSession` uses to know a card is in the air
— is macOS 26 but iOS **27**, and this app deploys to iOS 26, so on an iPad
running 26 nothing ever set `draggingID`: no dimmed card, no column highlight,
and nothing for a caret to hang off. `DraggableWhenOrdered` now takes the phone's
own trick on that build — the payload being asked for is the lift — and the latch
and expiry that make one pick-up one lift moved to `BoardStore.beginDrag(_:onLift:)`
so both surfaces share them. The caret itself no longer *needs* the flag either:
it is a fact about where the pointer is, and the card in the air is something it
checks against rather than something it requires.

**The iPhone's board pages take drops now, and used to take none at all.** They
were `TaskListView`'s `List` — rows hosted in collection view cells — and a card
released on one landed nowhere whether the target was the whole row or half of
it, measured with the zones and with a plain whole-row destination; the space
*around* the cards reached nothing either, so a column with nothing in it could
not be dragged to by any gesture. A `List` handles drags inside its own bounds,
which is the same sentence `InboxPanel` is a stack for. So a page is
`PhoneColumnPage` now: a `ScrollView` and a `LazyVStack`, the container the
desk's columns have always used, with the column's own drop destination around
it. The card's two half-row zones work on that surface for the first time, and
the ground under the last card and the whole of an empty column take a drop and
land it in that column. `UITests/CardDropTargetTests` runs on both idioms rather
than skipping the phone, and `UITests/ColumnDropTests` has a phone half of its
own — turned on its side, which is the one shape where columns share a phone
screen and a drop can therefore cross one.

**The phone's Inbox is the same story and the same fix.** `PhoneInboxSheet` drew
its cards with the same `List`, so nothing in the Inbox could be rearranged by
dragging and nothing could be dropped into it — on a surface whose desk
equivalent has done both since the panel existed. It draws them with the stack
now and carries `InboxPanel`'s own destination, the whole panel over: a card
released anywhere in it goes through `drop(_:onGroundOf: .inbox)`, and a card
released on one of its rows goes through the caret. `UITests/InboxSheetDropTests`
pins the half one finger can reach — a row dragged into the gap above another —
and reads the order off the screen rather than assuming the seed's, because it
rearranges the thing it measures. A card arriving from the *board* needs a drag
that outlives the sheet coming up, which is a second finger on the Inbox slot and
not something XCUITest can synthesise; what the destination calls is read out of
the source by `DragReorderTests` instead.

The container itself is one view, `PhoneCardStack`, because the argument for it
is one argument. The flat surfaces are still a `List`: Search, a saved view and
the Archive are filters over the board rather than places on it, and nothing can
be dropped into a filter. What the swap costs is the rows' `swipeActions`, and no
card in this app has swiped since 6.4.

**A drop on a list's own ground lands at the foot of it.** The ground is the
space around a column's cards — its header, the room under the last one, an empty
column — and it names no gap of its own, so something has to be the default. It
briefly *kept the row the card came in on*: a card third in Doing landed third in
the Backlog it was dropped on, on the argument that a card is dragged sideways
across stages of one piece of work and the row it was on is where the eye is.

**That is right on paper and wrong under a finger.** What a person aims at is the
space *under* the cards — on the phone it is most of the screen, everything below
the last card — and a card that lands halfway up the list they were pointing
below the end of has gone somewhere nothing marked. It reads as the card jumping
on release. So the ground is the plainest thing it can be:
`BoardStore.groundCaret(in:)` draws the caret under whatever is last, and the
drop follows it.

`UITests/GroundDropFootTests` is the half only a finger can ask, and it aims at
the dashed "+ Add task to…" row rather than at bare ground beside it, because
that row is where a thumb lands when it means "the bottom of this list" — it
passes the drop through to the page behind it, which is itself worth having
measured.

A pointer *inside* a card has named a gap, and that always wins: the foot is a
default for a drop that did not say where, and nothing more. An empty list gets
no caret at all, because a caret is drawn *by* a card on one of its edges and
there is no card there to draw it. The drop still lands; the column highlight is
the whole of the feedback for that one.

`drop(_:onGroundOf:)` is what the columns and both Inboxes call. It is
`move(_:to:)` with one refusal in front of it — see the exception below — and
that agreement is the point: a card arrives at the same place whether it was
carried there or sent by the move-to menu, the source list's board rows or a bulk
move.

The exception is a column the card is already in: a drop aimed at no particular
card is aimed at where the card already is, so it moves nothing, registers no
step, and draws no caret. The column still lights up. The two marks say different
things — the highlight is *which list the pointer is in*, the caret is *where the
card would go* — and there being nowhere for it to go is a true thing to draw.

`DropCaretTests` asserts the pair rather than the implementation: for each
direction it reads the caret, performs the move the drop closure would perform,
and reads the board order back, so a caret that lied would fail. The seed
fixture's columns hold one and two cards, which cannot tell "kept its row" from
"landed at the foot", so the ground tests deepen it to five and three. The edge itself
is a claim about pixels, so it is measured like one — the card is rendered
through `ImageRenderer` with and without the mark and the rows that changed are
compared. Swapping
`.top` and `.bottom` in the card fails that test and nothing else, which is
exactly what it is for. The raster's row order is measured rather than assumed,
by rendering a tile that is black on top and white below.

## Gestures and haptics on iOS

**The board pages one column at a time**, which seed task `t4` has described
since the first commit and which the dots at the top of the phone answered to in
no way at all. It is a horizontal `ScrollView` with a page per column, held by
`.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))` and bound to
`store.mobileColumnID` through `.scrollPosition`. `.viewAligned` rather than
`.paging` because a page is not always the viewport: in landscape three columns
share the screen, and `.paging` would step past two of them.

**The chips are the whole of the non-gesture route.** There was a second row
under them — a chevron either side of a strip of dots, each dot a button for its
column — which said in an alphabet of its own what the chips said by name,
directly above, in 46pt of a screen that has none to spare. It is gone;
`PhoneColumnPager` went with it, and so did the `Previous column` / `Next column`
strings. Tapping a chip still jumps to its column, the strip still scrolls the
current one into view, and the swipe is unchanged.

**A launch lands on a column the board has.** `mobileColumnID` is session state —
where the user is looking rather than anything about the board — so it is out of
`BoardSnapshot` and every run starts at the property's default, which is a *seed*
column's id. A board made in the app carries ids of its own — and now starts
with no columns at all — so opening straight onto one left the phone naming a
column that is on no board: every chip in the strip unlit, while the list, the
heading and the add row all showed the first column through `mobileColumnIndex`'s
`?? 0` — the surface disagreeing with itself about where it was. `init` now ends
in `detachSurfacesFromMissingColumns()`, the same reconciler `selectBoard`, a
column delete and an undo already run, so a launch is no longer the one way onto
a board that skipped it. A board that *has* the default keeps it, which is why
the seed board still opens on In Progress.

**The strip is portrait's.** Turned on its side the phone draws three columns at
once, each under a heading that gives its dot, its name and its count, so the
chips would be a second answer to a question already answered — in the dimension
a phone in landscape has least of. `columnChips` is behind `!isShort` in
`PhoneHeader`. The paging swipe is untouched in both shapes, and so is every
route through the header.

**A pull past the top of a list of cards checks iCloud.** Every surface that
holds cards and scrolls downward carries it — a board column, the Inbox, a saved
view, Search — and it is the system's own `refreshable` with the system's own
spinner, because a pull is what a finger already does when it wants a list to be
right. What the pull does, what it deliberately does not promise, and the one
surface that has no top to pull past are under **Pull to sync** in the Sync
section.

**Reorder within a column is a long press and a drag**, the same
`.draggable`/`.dropDestination` pair and the same `move(_:to:before:)` the desk
uses, under the same `allowsCardDrag` guard: where the cards on screen are not in
the board's own order, there is nothing a drop could mean. The lift is a long
press and the page turn is a pan, so the two do not compete. There is no non-drag
equivalent for a card's place *within* its column, and deliberately so — see
**Every drag has a way to say the same thing without one**, where Move Up / Move
Down went and what replaced them.

**The lift and the menu are one long press, and they have to be on one view.**
UIKit shares a single press between a view's `UIDragInteraction` and its
`UIContextMenuInteraction` — move while it is lifting and the drag takes it, hold
still and the menu does — and it only shares it when both interactions sit on the
*same* view. `.contextMenu` was applied by the list to the row and `.draggable` a
body deeper inside `PhoneTaskCard`, so they were on two: the menu's lift failed
the drag's gesture underneath it, and the only route left into a drag was hauling
the presented menu far enough to tear its preview out, which is a long way by
design. `PlatformTaskCard` now applies ``ReorderableCard`` and
``PhoneTaskRowActions`` side by side, in that order, on one view.

**This one cannot be pinned by a test.** XCUITest's runner is killed by its own
idle watchdog whenever a gesture is synthesised over a presented context menu, so
the press-past-the-menu case cannot be driven at all — measured, repeatedly, on
iOS 27. What the suites do cover is that the drag still works and still lands:
`CardDropTargetTests` and `ColumnDropTests` both press *short* of the menu, which
is the other half of the same gesture and the half a relocated modifier would
break first.

**A card can now be dragged to another column**, which it could not while the
pages were a `List`. Two things changed together. The page takes drops anywhere
in it — see `PhoneColumnPage` under **Drag and drop** — and, because the pager's
own scroll view now has drop destinations in its content rather than inside
collection view cells, it auto-scrolls under a lifted card: held at the leading
or trailing edge the page turns, and the card lands in whatever column it turns
to. Measured on an iPhone in portrait, from In Progress to Done, with the card
ticked on arrival the way every route into Done ticks one. Turned on its side two
columns share the screen and the drag needs no page turn at all. "Move to ▸" is
still there and is still the way a screen reader does it.

**No card swipes.** A card moves sideways once it has been picked up, and that
is the only time a sideways finger moves one. The two edges are gone from
`PhoneTaskRowActions`, which is now a context menu and nothing else, and the
paging swipe is untouched in both orientations.

This settles a disagreement the app was carrying. **The board's rows had already
given their swipe actions up to pay for paging**: a pan beginning on a list row is
claimed by whichever recognizer reaches it first and an enclosing scroll view
always does — measured both ways round, with a paging `ScrollView` and with a
`TabView(.page)`, and the leading swipe never revealed Complete; the board simply
turned to the next column. The failure requirement that would settle it the other
way needs a recognizer you own to state it on, and that one was SwiftUI's: a
`_UISwipeActionPanGestureRecognizer` inside a `List`, with no delegate of ours and
no seam to reach it through. (**The edge swipe below is the same rule won rather
than lost**, and the difference is exactly that: the recognizer there is one this
app makes.) So a sideways drag on a card meant one thing on the board and another
in the Inbox, which is worse than either answer on its own.

**Nothing became unreachable.** The menu was never a duplicate of the two edges:
it carries Move to, Archive, the reorder items and Copy Link, which no edge ever
offered, and it was already the only route for a reader on VoiceOver or Switch
Control, to whom a swipe is invisible. What the edges held — Complete and Trash —
is still the first and last thing in it. `BoardStore.isColumnPaging` keeps only
the layout question it was named for; it is no longer the answer to "who owns a
horizontal drag here", because that question now has one answer everywhere.
`UITests/RowSwipeTests` swipes a real card both ways on both surfaces and insists
that nothing comes out from under it — and, on the flat list, that the card has
not moved at all, since a row that slides 60pt and springs back has still opened
under the finger.

**Haptics are `.sensoryFeedback(_:trigger:)` throughout, with one exception** —
no generator to prepare, and the system setting is honoured by the API.
`.selection` on paging and on a tab change; `.selection` on ticking a sub-task;
`.impact(.light)` on a lift and on a drop. Nothing per keystroke.

**The exception is completion, and it had to move.** The tap for a card going
into Done was `.sensoryFeedback(.success, trigger: isDone)` on `PhoneTaskCard`,
which reads correctly and fires almost nowhere: the modifier fires when the value
changes on a view *still in the tree*, and finishing a card on a board takes it
out of the tree — the card moves to Done and the column page stops drawing it, so
the row and its modifier go away together before the change is seen. What was
left was a tap in the Inbox, where a completed capture stays put and merely goes
grey, and silence everywhere else on the phone. It is performed from
`CompletionFeedback` now, off the same announcement the chime rides —
`BoardStore` says a card was finished, and the announcement outlives whatever was
drawing it. That is a `UINotificationFeedbackGenerator(.success)` on iOS beside
the `NSHapticFeedbackManager` knock on macOS, kept rather than made per tap, and
a no-op on hardware with nothing to knock. The gate that keeps a bulk complete to
one chime keeps it to one tap for the same reason, and it is still only the edge
*into* done — never a reopen, and never an undo, which does not pass through
`performMove` at all.

**The lift bump is latched, because SwiftUI asks for the payload more than
once.** `.draggable` takes the payload as an autoclosure, and the comment here
used to say it is called when a session begins — it is called again for the
preview, and again as the view updates under the finger. Logged at three to six
calls for one pick-up, each of them a tap: what a card in the air felt like was
a rattle rather than a knock. `draggingID` is what tells one lift from the next,
and the payload closure is the phone's only signal for setting it — the desk sets
it from `onDragSessionUpdated`, which is iOS **27** against this target's 26
(checked in the SDK, not assumed). Every drop clears it through `endDrag`, so the
ordinary case is exact. The one case with no callback at all is a card let go
over nothing, which ends the session without telling anybody; a 20-second sleep
releases the flag so that card can tap again, longer than any drag a hand makes
and short enough to be forgotten before the same hand tries again. The drop bump
next to it is a plain counter — a drop has a handler, so it needs no latch. Both
fold into `onDragSessionUpdated` when the target moves, which is also when the
phone's card can start dimming while it is carried.

### The column chips carry the column

The phone draws a column as a chip in the header's strip, and until now that was
all a chip was: a switcher. Columns became board data in D1, but every call site
for the store's column mutations was in `Sources/Mac/`, so renaming, recolouring,
reordering or throwing away a column on this platform meant opening the drawer,
long-pressing the board row, and finding the column in the sheet that came up —
three surfaces deep for the four things a column *is*.

**A long press on the chip now opens the desk's column menu**, item for item:
Archive *N* Completed on a Done column with something in it, Edit Column…, Move
Left, Move Right, Trash Column. A context menu because the chip's *tap* is taken
and has to stay taken — it is the switcher — which is precisely the case iOS
offers one for, and is the same arrangement `BoardColumnView` has behind its ⋯.
Left and right rather than up and down: the chips are a horizontal strip over a
board that pages sideways, so those are the directions being looked at, while
`PhoneBoardEditor`'s own pair says up and down because there the columns are a
vertical list. Trash Column asks nothing, matching every other Trash here — the
act is undoable and the column waits thirty days — but it can still be *refused*,
so the strip keeps a `ColumnRefusal` and an alert exactly as the desk's header
and the board editor both do.

**Edit Column… opens `PhoneBoardEditor` with that column already unfolded** —
its new `expandsColumn` — rather than a column sheet of its own. Everything a
column can be changed to is already in that row: its name, its abbreviation, its
colour, where it sits, and whether it stays. A second surface holding a copy of
those four is a second place for them to drift. The board's own fields stay above
it, which is also true — a column belongs to a board, and the chip that opened it
is one of that board's. Arriving unfolded goes through the same `open(_:)` a tap
on the row does, split out of `toggle` so the two cannot disagree: the fields
bind to drafts, and a row unfolded without filling them shows the *last* column's
name under this column's heading. The sheet scrolls the row into view on the way
in, because the board name, the colour picker and however many columns come first
put the fifth column of five off the bottom of a phone.

`UITests/ColumnChipMenuTests` presses it, which is the only way: a context menu is
a `@ViewBuilder` handed to `.contextMenu` and no store knows what is in it. Two
things it measured are worth keeping. **A press of 1.0s does not raise the menu at
all** in the simulator — it fails on the first item every time, which reads
exactly like a menu that was never built; UIKit's own recogniser fires well
before that, and what needs the extra half-second is the chip's home in a
horizontal `ScrollView`, where a shorter hold is claimed by the scroller as the
start of a swipe. And **the board editor is left standing at the end**: the
header's Done is not the only button called that — one of the columns listed
under it is *named* Done and publishes its row under its own name — and a swipe
down over a `.large` sheet full of scrolling content scrolls the content.

### The edge swipe

**A pull inwards from the leading edge opens the drawer on the phone and the
source list on the iPad.** Both surfaces had one way in — the hamburger, the
toolbar's toggle — and a panel that slides out from an edge is one every other
iOS app opens by pulling from that edge.

`View.leadingEdgeSwipe(perform:)` in `Sources/IOS/EdgeSwipe.swift` is the whole
of it, and it is UIKit rather than SwiftUI on purpose. A `DragGesture` on a strip
at the edge is the obvious spelling and it loses to the board, for the same
reason the board's rows never managed to keep swipe actions: the board is a
horizontal scroll view on both idioms and its recognizer takes any pan that
lands on it.
`UIScreenEdgePanGestureRecognizer` is the one recognizer built for this — it is
what a navigation controller's interactive pop is made of — and SwiftUI exposes
nothing like it, so a `UIViewRepresentable` hangs one on the view controller
hosting the tree and a zero-sized anchor view is what finds that controller and
says when the tree goes away.

**Being a screen-edge pan was not on its own enough.** Measured on an iPhone 17
Pro, a pull from x = 0 across the board went to `UIScrollViewPanGestureRecognizer`
and ours never left `.possible`. What it needed was the failure requirement
stated outright — `gestureRecognizer(_:shouldBeRequiredToFailBy:)` returning true
for every competing pan, so they wait for this one to give up. That wait costs
nothing anywhere else: a screen-edge pan fails the moment a touch lands outside
its margin, so a scroll that starts anywhere but the edge is never held, and one
that starts on the edge and goes down is held only until the direction rules the
swipe out. Simultaneous recognition was the other spelling and is the wrong one —
it opens the drawer *and* turns the board to the next column, which is two
answers to one swipe. `UITests/EdgeSwipeTests` holds both halves: the pull that
opens, and a swipe from the middle of the board that must still page it.

**The drawer comes in under the finger**, which it did not at first. The
recognizer reported only `.began` and the handler set `isNavDrawerOpen = true`,
so the panel arrived whole and slid itself in over its own 0.28s while the finger
went wherever it liked: a pull of a fifth of the screen and a pull of all of it
were the same act, and neither had anything to do with where the drawer was
drawn. `EdgePan` reports every phase now — `distance` and `velocity` flipped back
to *inwards* on the way out, so no call site has to know which way the layout
runs — and `PhoneRootView.drawerPan` turns the distance into a fraction of the
panel's own width — asked of `PhoneNavDrawer.width(in:screen:)`, the same
function the panel asks, or a finger crossing 734pt to open a 338pt drawer
leaves the drawer trailing behind it — and hands it to
`PhoneNavDrawer.progress`. The panel is offset by
what is left of that fraction and the scrim darkens with it, so a drag half-way
in is half-way to hiding the board.

Three things fall out of that being a *position* rather than an animation. The
panel comes into the tree inside a transaction with animations off, because its
own `.transition(.move(edge: .leading))` would otherwise be a second opinion
about where it is. The lift is the only animated part: past halfway it settles
open, short of that it goes back, and either way a throw over 350pt/s decides
instead — which is how every drawer on this platform reads a pan. And the closing
settle has to *finish* before `isNavDrawerOpen` goes false, so `Motion.run` grew
a completion-carrying spelling; under Reduce Motion the animation is `nil` and
the completion runs at once, which is the right answer rather than a special
case. Once the drag is over, `progress` goes back to 1 and the drawer is the
transition's again — the hamburger, the rows and the ✕ never learned about any
of this.

`EdgeSwipeTests` gained the half that can tell the two behaviours apart. An
intermediate frame is not something XCUITest can be asked about, but the two ends
of the same *slow* drag are: a fifth of the screen has to leave the drawer shut
and four fifths has to open it, and under the old rule both opened it. Slowly in
both cases, because a throw is allowed to open the drawer from anywhere — which
is also what makes the full-width swipe above pass whatever its distance.

The iPad's half is not a gap SwiftUI fills either. `UISplitViewController` has
`presentsWithGesture` and it is on by default, but measured on an iPad Pro 13" in
portrait the pull left the source list exactly where it was — the board's scroll
view again. `PadRootView` takes the same modifier, and it only ever *reveals*:
in landscape the list is already beside the board, and a gesture that put it away
would be the swipe undoing itself on the one shape where the edge and the list
are the same place.

**The edge is leading, not left.** In a right-to-left layout the drawer comes
from the other side — `ZStack(alignment: .leading)` and the panel's
`.transition(.move(edge: .leading))` both mirror on their own — so the gesture
has to come from the side the panel does. See **Language and direction** for the
two values in this app that do not mirror themselves.

### Landscape

The phone is no longer locked to portrait. `project.yml` grants it portrait and
both landscapes — no upside-down, matching Apple's own phone apps — and the board
lays out `verticalSizeClass == .compact ? min(3, columns) : 1` columns per
screen through `containerRelativeFrame(.horizontal, count:span:spacing:)`.

**Three, and it divides exactly.** It was two, and the arithmetic is the reason
it did not have to stay two: the pager divides the width *inside* the safe area,
so the count is a division rather than an estimate. Measured on a 17 Pro on its
side — 874pt of window, 62 either side of the sensor housing, 750 left — the
pages came out 375 and 375 at two, and 250, 250 and 250 at three, in both cases
filling the screen edge to edge with no half column showing. What a page pays is
the card inside it: a row falls 335 → 210pt and the title in it 267 → 142, which
is two or three lines of a card title where it was one or two. What the board
buys is the third column of four, which on the seed board is the difference
between watching a card leave Up Next and arrive in Done and having to swipe to
find out where it went.

The count is capped at the board's own column count, which two never needed: a
two-column board divided into three leaves a third of the screen showing
nothing, and a board is allowed to have two columns.

**And a Max-class phone actually reaches it.** The multi-column board is for the
devices with the width to hold more than one, which are precisely the ones that
report a *regular* horizontal size class in landscape — so while the root asked
the size class alone, an iPhone 17 Pro Max at 956×440 was handed `PadRootView`
and this layout never ran on the hardware it was written for. See **The iPad**
for the rule that replaced it.

A short screen is 402pt tall, and the portrait chrome left **191pt of list** in
it: one card. So the compact height sheds chrome rather than columns — the serif
title drops 30 → 22pt and one line, the stack spacing 16 → 9, and **the column
selector goes**: the chips row, with the 10pt of clearance the pages take below
it. (There was a second row here — the chevrons and dots — costing another 46;
it is gone from both shapes now, and portrait got that back too.) The list's top
inset falls to 0, and its bottom — once 92, the room to scroll a last card clear
of a floating bar — to 24, because the bar is not down there any more. Portrait
is byte-for-byte unchanged otherwise: `isShort` is false everywhere in it. What
names the column instead is the page's own dot-name-count heading, drawn whenever
more than one page shares the screen — which is exactly the case where the chips
are gone.

Two things follow from more than one column being visible at once.
`mobileColumnID` is the **leading** one, because `.scrollPosition(anchor:
.center)` lands between pages —
so with the board scrolled to the end the last column is on screen without its
chip lit. And the add row, the empty state and the add action all take the
*page's* column rather than the current one, since the page a finger is over is
not always the one the pager is on.

**The tab bar moves into the header, and the words come off it.** Board, Inbox,
Search and the quick-capture **+** ran along the foot, where between them they
cost 130pt of a 402pt screen: the pill, the button, and the room under the last
card to scroll clear of both. That is a third of the axis this shape has least
of — so `PhoneTabBar` takes a `Placement`, and landscape draws it in the title
row, between the board's name and the ⋯. Same three slots in the same order,
same button after them, and **nothing pays for it**: that row is already drawn,
already 44pt tall, and the middle of it was a serif name with the whole width of
the screen after it.

**It stood on end up the leading edge first**, and that is worth writing down
because the rail was not wrong — it bought the 130pt of height back, and charged
the board 76pt of width for it through a `safeAreaInset(edge: .leading)`. The
header row is the third answer and the only free one. What the rail leaves
behind is the reason the pager is now **`.clipped()`**: a `ScrollView` reaches
past the safe area by design and insets only its content, so the next column
along is drawn in the strip beside the sensor housing. The rail used to stand in
that strip with an opaque ground and hide it; with nothing there any more, the
pager is held to the frame it was given. A no-op in portrait, where the
horizontal insets are zero.

Each slot is a glyph and a word along the foot and **the glyph alone in the
header**. The glyphs are the app's own vocabulary rather than a new set — the
board's `square.grid.2x2`, the tray `SavedView.inbox` is drawn with everywhere
else, and the header's magnifier — so the same place has the same mark wherever
it is named. Each button says its own name through `accessibilityLabel`, so
VoiceOver meets the same three names in both shapes and never sees the
difference. The one place the glyph gives way is the *portrait* bar at an
accessibility size: a 12pt label there is already scaling to its floor to fit a
third of a phone's width, and a glyph beside it takes the last of that room and
truncates the word — so above `dynamicTypeSize.isAccessibilitySize` the word
takes the slot back.

**The header's slot draws smaller than it claims**, which is the trade the
hamburger and the ⋯ beside it already make. The chip is 34pt — their size, so
the row reads as one row rather than as a bar dropped into a title — and 5pt of
padding round it carries the target out to the 44 a finger needs. Padding rather
than a `frame`, because the glass pill wraps whatever the slot returns: a 44pt
frame would put the material 5pt out from the chip on every side, which is a
pill drawn round its own gaps. The bar's own `padding(.bottom, 3)` puts its foot
level with theirs, so joining the row costs it no height at all.

`UITests/TabRailTests` is the only thing that can check it, for
`ColumnStripTests`'s reason and one more: it is a size class, and it is a
*frame*. It turns the phone and reads where the **+** and the Board slot landed
— in the top fifth of the screen rather than over the foot, after the drawer
button and before the ⋯ — and that the slot is a 44pt square rather than the
~100pt run a word would need, which is what pins "only the glyphs remain". It
also checks the drawer button starts within a tenth of the width, which is the
board having the leading edge back. The suite keeps the older name; the claim it
makes has not changed, only where the frames have to land.

**The Inbox panel is no thicker turned than it is upright.** A detent is a
request UIKit grants only where the height is regular; in a compact one it
ignores the detent and lays the sheet out at the whole screen, so the Inbox on
its side was a full-screen page with its cards stretched 874pt across — thicker
turned than upright, which is the wrong way round for a panel meant to be *over*
something. `PhoneInboxSheet` sizes itself now: the panel is capped at the
screen's **short edge**, which is that phone's own portrait width held either
way up, and stands on the bottom edge as a card with all four corners rounded,
nine tenths of the height with the board's strip above it. That is the drawer's
rule reached the drawer's way — see `PhoneNavDrawer.width(in:screen:)` — and
upright the short edge *is* the width, so it is one line that reads the same in
both shapes rather than a branch. The edge is put back together from
`GeometryReader`'s `safeAreaInsets`, because inside a sheet the height arrives
short by the home indicator's 21pt and 381 is not a phone's portrait width.

**What that shape cannot have is the board behind it.** A sheet that covers the
screen has the view which presented it taken out of the hierarchy underneath, so
clearing the sheet's own ground uncovers the *window* and nothing else — measured,
the panel came out standing on plain white. Upright the system dims the board and
leaves it showing through the top tenth; on its side the panel draws the drawer's
own `palette.scrim()` in that place at the same weight, and takes the tap on it
that puts the panel away, because dismissing by tapping outside is the system's
job at a detent and this is the one shape where *outside the panel* is still
inside the sheet. Putting the real board back there means the Inbox ceasing to be
a sheet in landscape and going back to a hand-rolled overlay — the scrim, the
transitions, the drag and the `.isModal` it deliberately gave up. The system's
grabber moves with the *sheet* rather than with the panel, so it would float over
the board most of a screen above what it belongs to: it is hidden there and the
panel draws its own.

`UITests/InboxPanelTests` gained the case. It turns the phone and reads a card's
width against the phone's own upright width, both ends of the header against the
screen's, and the header's distance from the top — the portrait claim above made
again in the shape that lost it. With the cap taken out the card measures 642pt
against a 402pt phone, which is what the suite is for.

The add-column composer used to be the one place landscape was worse: 402pt minus
a software keyboard leaves 238pt for a composer that was around 200pt tall, so its
last row could be clipped above the visible area. Its Role picker sat **above**
the Name field for that reason — naming the column raises the keyboard, and with
Role below it the picker was measured unhittable and every column made in
landscape came out a Backlog. The roles went in v9, and the height they freed is
what a Short field and a row of swatches have since spent.

**So the composer lays itself out to the room it has**, through the
`ViewThatFits(in: .horizontal)` `MoveToPicker` already uses: Name, Short and the
six colour swatches on one row where that fits, and the swatches under the two
fields where it does not. Name and Short stay side by side on every surface — an
abbreviation is a word rather than a sentence, so it is the half that takes a
fixed width — and the Name field keeps a floor of `Metrics.nameFloor` — 140pt —
so "fits" cannot come to mean a name field squeezed to nothing. A landscape phone
is the one surface with no height and plenty of width, so it is the one that
takes the single row; the desk, the iPad and an upright phone all put the
swatches under the pair, and all have the height to.

**A column's own editor is the same three controls in the same arrangement**, and
literally the same code: `columnShape(name:nameFocus:short:shortFocus:dot:setDot:)`
is what both the composer and an unfolded row draw. They are the same column a
moment apart — the composer *is* the column, before it exists — and the editor
used to stack Name over Short over Colour while the composer put the fields side
by side, which is two layouts for one thing and two places for them to drift.
This file has been through that once already; `renameColumn(_:to:short:)` exists
because the phone could rename a column and nothing could rename its
abbreviation. `setDot` is the whole of what differs between the two callers: the
editor recolours the column as a swatch is pressed, and the composer holds the
pick on a value until Add Column is, because there is no column to recolour yet.

That the stacked form does not fit in landscape is measured rather than reasoned
about. `BoardSettingsSheetTests` turns the phone, opens the composer, types a
name, and reads `isHittable` off the Short field, a swatch and the Add Column
button — which is what being under the keyboard looks like from outside the app.
On an 874x402 phone the keyboard's top edge is at y=224. Stacked, the Short field
ran 215→259 and reported `hittable=false`, and Add Column at 273→317 was under it
altogether. In one row the fields and the swatches share y 66→110 and Add Column
sits at 124→168, clear by 56pt; upright, where the keyboard starts at 583, the
swatches drop to 425→469 and the button to 483→527. The suite skips itself where
no software keyboard comes up, because a simulator with a hardware keyboard
attached would pass it whatever the layout did.

## Persistence

The board is saved as one JSON document — `BoardSnapshot`, written by
`BoardFile` to `Application Support/SimpleKanban/board.json`. On macOS the app
is sandboxed, so that resolves inside
`~/Library/Containers/com.n14395.SimpleKanban/Data/`.

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

  A blocked *file* is only a blocked file. The save funnel's followers — the
  record store, and outside the test host the reminders, the Spotlight index
  and the widgets — still run on every save, because none of them is the file
  being protected and a blocked session's edits exist nowhere else: they used
  to accumulate in memory reaching nothing at all, and a quit kept none of
  them. The one thing withheld is the write itself. The iOS banner that states
  the condition now carries **Export…** — the copy of the session's work the
  user can put somewhere they chose — and on the desk File ▸ Export Board…
  has always been there. `PersistenceTests/aBlockedSaveStillReachesTheRecords`
  pins the arrangement, reaching the blocked state the honest way: a corrupt
  board in a directory nothing can write into.
- **Older files are migrated, not guessed at.** `BoardSnapshot.currentVersion`
  is 14. The version is read out of the raw JSON *before* anything is decoded,
  because synthesised `Codable` throws `keyNotFound` for a key the older shape
  never wrote — a property default does not make a field backward-compatible.
  Only an `Optional` tolerates absence, which is why `archivedAt` is one.
  `BoardMigration.swift` holds the frozen shapes and **one function per step of
  a chain**:
  - **v1 → v2** — string ids become UUIDs, `due` becomes the day it always meant,
    each rendered sentence is kept as `.legacy`.
  - **v2 → v3** — nothing written before v3 was archived.
  - **v3 → v4** — the compiled-in columns become data with UUID ids, keeping their
    name, short name, dot and order; every legacy string id is mapped — `"inbox"`
    among them, so nothing is stranded — on the task *and* inside each `.moved`
    activity entry, which is what `reopen` reads. A card whose column this does
    not recognise is treated as an Inbox card rather than dropped.
  - **v4 → v5** — the flat column list becomes a *board's* columns and the Inbox
    goes global. One board is made, named "Northwind iOS 3.0", dot `.accent`,
    prefix `"NW"`, adopting the v4 columns whole so no id has to be rewritten, and
    it becomes the active board. Every card in the old Inbox column becomes
    unfiled, because the Inbox is not a column any more, and every other card
    joins the board. "The old Inbox column" is spelled as *a column this board does
    not have*, which also catches a card left pointing at a column a hand-edited
    file deleted — an unplaceable card is still the user's, and the Inbox is where
    it can be found again. Codes are left exactly as they are: renumbering NW-118
    to IN-118 because the card happened to be in the Inbox would break a label
    someone may have pasted into a commit message. The board's id is fixed rather
    than fresh, so migrating the same bytes twice names the same board both times.
  - **v5 → v6** — `Priority` stops storing the words the interface draws. Its raw
    values were "High", "Medium" and "Low", so the board file carried English that
    doubled as UI text and a translated build would have had to rewrite everybody's
    boards to show a translated priority; they are now `high`, `medium` and `low`,
    and `Priority.displayName` is the only thing that speaks a language. This is the
    one step with no frozen shape of its own: nothing else about the file moved, and
    `Priority.init(stored:)` answers to either spelling, so the current decoder reads
    a v5 file whole and the step has only the stamp left to do. It is still a step,
    because the bump is what makes a v5 build *refuse* a v6 file rather than decode
    no priority in it and quarantine the user's board as corrupt. Note the v1 step
    reads `priority` as a bare `String` rather than through the decoder, so it goes
    through `Priority(stored:)` too.

  - **v6 → v7** — the file gains `trash`: the tasks, columns and boards the user
    has thrown away and can still get back, which is what **The trash** is about.
    Purely additive and defaulted, so this is the second step with no frozen shape
    of its own — a v6 file simply has an empty trash, which is the truth about it.
    The bump is the whole of the step, and it is the same argument v5 → v6 makes
    from the other side: `Codable` ignores keys it does not know, so a v6 build
    handed a v7 file would read the board *perfectly*, notice nothing, and write
    it back with the trash silently dropped — a downgrade quietly destroying the
    deleted work the trash exists to hold. With the bump it refuses the file and
    says why. It is also why `BoardSnapshot.init(from:)` is written out rather
    than synthesised: a decoder throws `keyNotFound` for a key the file has not
    got and a property default does not save you, so `trash` is read with
    `decodeIfPresent` and every other key stays strict — a board file with no
    `tasks` key is not an empty board, it is not a board file.

  - **v7 → v8** — `Priority` gains `max`, a fourth case above High, and what a
    card is minted with moves from `medium` to `low`. Neither touches the shape,
    so this is the third bare stamp — a v7 file has no `max` in it and every card
    in it already carries a priority of its own, which is why the default moving
    rewrites nothing that already exists.

    The bump is the sharper version of the v5 → v6 argument. `Priority.init(from:)`
    *throws* on a token it does not know, and a `Codable` throw is not local: a v7
    build handed a board with a single Max card on it fails to decode the whole
    file and quarantines the user's board as corrupt. With the bump it refuses the
    file up front and says why. The migrations do not read `Priority.default` —
    a file that predates the field means what the default was when it was written,
    which is `medium`, and re-reading old boards through today's default would
    silently re-rank them.

    **Sync has no such stamp.** A CloudKit record carries the priority as a bare
    string and `BoardSyncStore` falls back to `medium` for a token it does not
    know, so a device on an older build shows a Max card as Medium — and writes
    Medium back if it edits that card. There is no version to refuse on, which is
    what **What CloudKit will not do for you** is about; the board *file* is where
    the guarantee lives.

  - **v8 → v9** — `ColumnRole` goes. Up to v8 each column stored `backlog`,
    `active` or `done`, and a board's Done column was the first one whose role
    said so; it is now simply the board's **last** column. The step is therefore a
    *reorder*, and only for boards not already in that shape: whichever column v8
    would have sent a tick to moves to the end of its board. Every column is kept,
    the order of the rest is kept, and no card moves — a card sits in a column,
    and the column has come with it.

    It is the one step that needs something the decoded value no longer has. v9
    removed the field, so the current decoder throws the roles away on the way in;
    `BoardSnapshot.legacyDoneColumns(in:)` reads them straight out of the bytes
    with a five-line `Decodable` rather than a frozen copy of the whole v8
    snapshot, because one key of one array is all the step needs. It is silent
    about failure on purpose: a v1–v4 file has no `boards` key at all and yields
    nothing, which is right, since those are rebuilt out of `BoardColumn.workflow`
    on the way through and already end in Done.

    **The one board this changes the meaning of** is one with more than one `done`
    column. v8 treated a card in *any* of them as complete while sending new ticks
    only to the first; v9 has one Done column, so cards left in the others read as
    unfinished again. Nothing is lost, and the state it gives up is one the app
    never had a way to show. `board-v8-done-adrift.json` is the fixture that would
    catch the reorder going missing.

    **Sync keeps the field and stops reading it.** A CloudKit schema is additive
    only once it is in production, so `StoredColumn.roleKey` stays —
    `BoardSyncStore` writes `"done"` for the last column and `"backlog"` for the
    rest, which is v9's rule spelled in v8's vocabulary, so a device on an older
    build still finds exactly one Done column and finds it in the right place.

  - **v13 → v14** — a column gains ``BoardColumn.limit``, its WIP limit. Purely
    additive and optional, so it is another bare stamp: a v13 file has no
    `limit` on any column, a synthesised decoder reads an absent `Optional` as
    `nil`, and `nil` is exactly what a column drawn by a build without limits
    meant. `board-v13.json` is the fixture that says so.

    The bump is the trash's argument again, from the other direction: without it
    a v13 build handed a v14 board would decode it *perfectly*, notice nothing,
    and write it back with every limit the user had set silently gone. **Sync
    has no such stamp** — `StoredColumn.limit` is optional and defaulted, so a
    device on an older build reads a limited column as unlimited and writes that
    back if it edits it, exactly as `Priority.max` does. The board *file* is
    where the guarantee lives.

  Those last two were planned as **one** step to v4 — "boards and columns" was a
  single item — and shipped as two because each half is separately verifiable and
  a half-migrated file is not: v3 → v4 turns the compiled-in columns into data
  without moving them, and v4 → v5 hands them to a board and takes the Inbox out
  of the column list. So the version reached 5 rather than the 4 the plan named,
  7.2's separation of stored values from display strings took it to 6, the
  trash took it to 7, and the fourth priority took it to 8.

  A v1 file therefore walks through exactly the same v4 → v5 code a v4 file does,
  and adding v9 costs one shape and one function rather than an edit to every
  decoder — widening an old decoder to reach the current shape instead would make
  every future field silently rewrite the past. The pre-migration bytes are copied
  to `board.v<n>-<stamp>.json` first: a migration is the one moment the old shape
  stops existing anywhere. `Tests/Fixtures/` keeps a real file per era to migrate
  against: `board-v1.json`; `board-v1-minted.json`, whose board went on minting
  codes after it was written and so pins `nextSerial` continuity too;
  `board-v2.json`; `board-v3.json`; `board-v4.json` — those three generated by
  round-tripping a real snapshot through this codebase's own encoder rather than
  typed by hand, and equal field for field to `TestBoard.tasks` — and
  `board-v5.json`, the v4 one carried forward a step by hand and given all three
  legacy priority spellings, on the task *and* inside a `prioritySet` activity
  entry, which is the half a raw-value swap forgets; and `board-v6.json`, the
  same shape one stamp further on, which is what makes the "reads a file with no
  `trash` key" claim a test rather than a sentence. Every later era has one too
  — `board-v7.json`, `board-v8-done-adrift.json` above, and `board-v9.json`
  through `board-v13.json` — so no step of the chain is exercised only by a
  synthetic value: each is the bytes a build of that era would have written, and
  each carries whatever its own version was *for*, which is what makes a bare
  stamp a step that can fail. Drop a newer one in and `MigrationChainTests`
  picks it up off the bundle with no code change.
- **Rolling backups.** The live file is copied to `backups/board-<stamp>.json`
  beside the board when the newest backup has aged past 15 minutes, and as many
  of the newest as Settings ▸ **Backups to keep** says are kept — 25 by default.
  Taken on the debounced path only, never at quit.
  `backupNow()` is the forced counterpart, used before a restore or a reset: it
  takes the next second rather than skipping when a backup already exists for
  this one, because "there was already one this second" is not an answer at the
  moment the board is about to be replaced.
- **Failures reach the user.** `BoardFile.write` throws rather than logging —
  `OSLog` is not a user interface, and an app that has silently stopped saving
  looks identical to one that is working. The store keeps the last error, the
  macOS status bar shows it — and when there is none, how long ago the board last
  saved — and a load failure raises an alert at launch naming the file the
  damaged board was kept as. On iOS there is no status bar, so a write failure
  takes a dismissible banner in the root's top safe-area inset — an inset rather
  than an overlay, so it cannot sit on top of the header it is warning about.
  The launch alert is on `RootView` and has always been on both platforms.
- **`nextSerial` is saved.** Without it a new session restarts at NW-140 and
  issues codes that collide with tasks an earlier session already created.
- **The active board is saved; the surface is not.** `activeBoardID` survives a
  relaunch because which board you are on is where your work is. It is
  deliberately *not* part of `BoardMutation`, so undoing a board delete brings the
  board back without dragging you back to it.
- **Session state is deliberately excluded** — selection, drafts, search query,
  current tab, which surface is showing, the active saved view and drag state
  belong to a sitting, not to the board.

`BoardStore(file: nil)` is an in-memory store that never touches the file, which
is what previews and tests use — see **Tests**.

### Identity and timestamps

A task's `id` is a `UUID`. `code` — "NW-118" — is the human-facing label a task
carries, minted from the destination's prefix and one file-wide counter, and
meant to be read out loud rather than looked at: it is not drawn in either
editor; see **Codes**. Nothing keys off it, so renumbering or
importing a task cannot break a reference. v1 files stored string ids (`"t1"`)
that nothing referred to, so the migration mints fresh UUIDs for them.

Every task also carries `createdAt` and `updatedAt`. `updatedAt` is stamped
centrally by every mutation — it is what the detail surfaces show, what
"Recently updated" sorts on and what the "This week" meter's window is measured
in, and deliberately not what the search memo keys off, for the
reason **Search** gives. A migrated task takes both from its own activity feed,
which is the only evidence a v1 board carries about when anything happened.

### Accent

**The accent is a parameter of the theme.** It began as `AccentTheme`, four whole
palettes with a swatch row in Settings; it is now `Theme.highlight`, which carries
the accent, its soft wash and the ink that goes on top of it as three fields a
theme states outright. The swatch row is gone, and so is the enum — see **Themes**
for what replaced it and for how a board that had chosen Pine or Indigo keeps its
colour across the v12 migration. The choice is still saved with the board, for the
reason **Settings** gives.

`SwatchColor` keeps literals as `.rgb(hex, opacity:)` rather than a built
`Color` — that is what makes a user-created label encodable, since `Color` is
not `Codable`.

**`palette.onAccent` is what goes on top of `palette.accent`** — a filled
button's label, the tick inside a completed checkbox, the current chip in a row
of chips. Seven views wrote it as a literal `.white`, which is a C2 violation and
also wrong: three of the four accents are dark, saturated colours in either
scheme and white is right on them, but `.ink` *is* the ink colour, and ink in dark
mode is 0xEEEAE2. White on it scores 1.2:1 — the source list's capture button, the
completion tick, the phone's pager chips and the due-date presets were all blank
for anyone using the ink accent after dark. On-accent follows the scheme the
other way round, and `PaletteSemanticTests` holds all eight accent-by-scheme
pairs above 4.5:1, which is the only property of a colour pair a test can hold
and the only one that matters here.

**`palette.scrim(_:)` is the same trap from the other end.** The two panels that
*cover* a surface rather than sitting beside it — the iPhone's navigation drawer
and its Inbox slide-over — both wrote their wash as `ink(0.3)`, and ink in dark
mode is that same 0xEEEAE2. Opening either one laid a near-white veil over the
board: the screen lit up instead of dimming, which is the one thing a scrim
exists not to do. A scrim is a **shadow** rather than an ink — it is the absence
of what is behind it — and `shadow(_:)` is already the colour that goes to pure
black after dark, for precisely this reason. It went unnoticed for as long as it
did because the two spellings are the same 0x171310 in light mode, so the scheme
anybody checks is the scheme where they agree; light mode is unchanged to the
byte. Dark mode is *heavier*, at 0.5, because the board is 0x131110 to begin with
and black at 0.3 over near-black is not a wash anybody can see. The fraction is
for a panel being dragged in, whose scrim arrives with it. `PaletteSemanticTests`
composites the scrim over the board and asserts it came out darker, in both
schemes — because the wrong one is the one nobody looks at.

## Settings

One `SettingsView` in `Sources/Shared/`, at `.desk` inside the macOS `Settings { }`
scene — which is where ⌘, comes from, so `AppCommand` neither declares it nor has
to — and at `.sheet` on iOS, raised by `store.isShowingSettings`.

**Four subjects, where there were eight.** Trash, Appearance, Board,
Notifications, Sync, System, Labels and Data was a list long enough that finding
a setting meant reading every name on the way to it, and half of those names led
to a pane holding a single row: Sync was one switch and a paragraph, Labels was
one button that opens a sheet, System was two switches, Appearance was a swatch
row and a menu. A subject that holds one control is not a subject; it is a row
that has been given a tab of its own, and everybody pays for it on the way past.
They paid hardest on the phone, where the strip shows about three chips at a time
and the other five were off the side of the screen. So:

- **General** — what the app looks like and how it comes up. *Appearance* (the
  light/dark/system override, the theme browser behind it — see **Themes** — and
  the app icon picker behind the row under it, see **The app icon**)
  and *At launch* (reopen the last view, and — on the desk and the iPad, where
  the Inbox is a panel beside the board rather than a sheet over it — open the
  Inbox with the board unless it is empty), plus *This Mac* on the desk: open at
  login and
  the menu bar item. Those last two are still the desk's alone, but the `#if` is
  now around **two rows** rather than around a case of `SettingsTab`, so
  `allCases` is the same list on both platforms and neither has to filter it.
- **Board** — how a board behaves: the order cards sit in, how much a card shows,
  where new ones land and when they are due, when Done is swept, what a week
  means — and, under *Labels*, the Phase B manager, opened as a sheet from a row
  so there is one label surface and not two. The labels are the board's, so the
  row is on the board's pane.
- **Notifications** — due-date reminders and the time of day they arrive. The one
  subject that was already the right size, and the only pane that is still a
  single panel.
- **Data** — where the board lives and every way of getting it back: *iCloud*,
  *Kept copies* (how long the Trash holds things, how many backups, and the
  restore list), *The board file* (export, Markdown export, import, and the file
  itself), and *Starting over*.

**The Trash is not in Settings at all** — see **The trash** for where it went and
why.

**Both surfaces show one subject at a time**, and both read the same
`SettingsTab` — one `CaseIterable` carrying each subject's name and glyph, which
the desk turns into `.tabItem`s and the sheet into a strip of chips. The list was
made shared because the two had already drifted: **System** sat in the macOS
`TabView` with no `.tabItem` on it at all, so its pane was reachable only by
clicking the unlabelled gap in the toolbar where its name should have been. A
case that carries its own name cannot go unlabelled, and `SettingsTabTests` asks
the rest — that there are at most four, that the names are distinct, that a glyph
is one the system actually has (an unresolved `systemImage` draws nothing and
says nothing), and that the Trash is not among them.

**The iOS strip is at the top, and it is deliberately not a `TabView`.** A tab bar
on iOS is at the bottom, and it would land on top of the version row this sheet
already puts in its bottom safe area. A row of chips under the title is both the
thing that fits and the closer likeness to the desk, whose subjects are also
along the top. It kept its sideways scroll and its masked ends after eight became
four — four chips fit across a phone at the system type size and stop fitting a
size or two up, and a strip that can scroll costs nothing on the day it does not
need to. The mask is there because a chip cut off by a fade reads as "there is
more this way" while one cut off by the sheet's own edge reads as the end of the
list, which is what the strip looked like at eight: measured on an iPad, the
fifth chip finished a few points short of the edge and the last two subjects were
invisible with nothing to say they were there. Choosing a chip scrolls it to the
centre, and the pane is rebuilt on `.id(selection)` so a new subject opens at its
own top rather than at the offset the last one was left at.

The same section views feed both surfaces, so there is one Notifications pane and
not two. **A pane holding more than one panel puts a heading over each** —
`group(_:content:)` — and a pane holding one puts none: a heading is what
separates one section from the next, and there is nothing to separate when the
desk's toolbar has just said the word and the window title says it again above
that, and the sheet's chosen chip is sitting directly over the panel with the
same word in it. Three copies of "Notifications" down the left of a pane is how a
settings surface looks when it was a scroll last week. With four subjects instead
of eight, a pane is a page rather than a list, and a page of four groups without
headings is one long strip of switches to read from the top every time. Each pane
scrolls inside itself rather than growing the window — Data grows with what the
user has, and a settings window a thousand points tall because somebody has a
fortnight of backups has stopped being a settings window.

**Rows are full-width and leading-aligned**, which is `row(_:)`'s doing and was
not always true. A `Toggle` and a `DatePicker` are as wide as their own label and
no wider, so left to themselves they *centre* in a panel whose width some other
row decided. Nothing shows that while a pane is one long list of `choice` rows
holding the panel open; it is glaring the moment a group holds two switches and
nothing else, which is what **At launch** is — measured, its two sat in the
middle of the panel with a finger's width of nothing either side.

**`UITests/SettingsTabsTests` is what can tell a strip from a scroll.** Every
section view is the same object it was when they were stacked in one `ScrollView`;
what changed is that three of them are not *built* while the fourth is showing,
and no store knows that. So it opens the sheet on both idioms, walks the chips,
and checks each subject's own control arrives **and the one before it has gone** —
which a scroll would fail on the second half while passing the first. Each
marker is picked from a group its pane holds alone, so a marker two panes could
show cannot pass the suite while the strip does nothing.

The version is at the bottom of the iOS sheet, in a 44pt row reading
"Simple Kanban · Version 1.0 (1)"; macOS has the app menu's About window instead,
which is where **Check for Updates…** lives — see **Packaging, the icon and the
update check**.

macOS reaches it through ⌘, and nothing else has to be built. **iOS has three
doors, all of which had to be added**: a Settings row at the foot of the phone's
nav drawer, which closes the drawer before raising the sheet because a sheet
presented under an open overlay is one nobody can touch; an item in the phone's
`…` menu, added when that menu stopped being a copy of the drawer and had room
for something the drawer alone was holding; and a row under Labels in
`BoardSidebar` for the iPad, which is the whole of that platform's chrome. Two
doors on the phone is not the duplication the menu's board and view items were:
those led to *places* the drawer draws better, and this leads to a sheet that
neither surface draws at all. The
`#if os(iOS)` around the sidebar's row is about reachability rather than size — a
second door on macOS would duplicate the app menu's.

### Where each setting lives

The rule is the one `PreferenceTests` enforces: **`BoardSnapshot` is the board —
what a second machine restoring from an export would need. Everything else is a
preference and belongs in `UserDefaults`.** A preference in the snapshot costs
twice: it is a schema change needing a version bump and a migration (C7), and it
*travels*, so an import reaches across and changes the importing machine.

- **Appearance** — `@AppStorage("SimpleKanbanAppearance")`, an `AppAppearance`.
  This is the spec's `state.dark`, the one state field dropped during the port,
  back as a preference. `RootView` resolves `appearance.colorScheme ?? colorScheme`
  into the palette *and* applies `.preferredColorScheme` below it, because
  `preferredColorScheme` propagates downwards and the view that sets it does not
  see it.

  **Anything presented from *outside* that has to resolve the palette itself.**
  A `ViewModifier` applied to `RootView` sits above the
  `.environment(\.palette,)` `RootView` publishes below it, so
  `@Environment(\.palette)` there reads the default *light* palette — and a
  macOS `Window` scene is outside the board window altogether. Nothing about
  that shows in light mode; in dark mode the surface opens cream-coloured over a
  dark board. It has caught the About panel, the first-run picker, the iOS
  settings sheet and the save-failure banner, so each of the five now builds its
  own `Palette` from the override and the colour scheme, and
  `SystemWiringTests` holds the rule: no `ViewModifier` in `SimpleKanbanApp.swift`
  reads the palette out of the environment.
- **Sort order** — `UserDefaults`, key `BoardStore.sortOrderKey`, read back only by
  `BoardStore.restored()` so a preview or a test never picks up the developer's
  setting, and written only when the store has a file. `.manual` is the board's own
  order and the only one a card may be dragged under: a drop is an index into the
  unfiltered `tasks` array and means nothing once something else decides the order,
  so `allowsCardDrag` is false for the other three. It applies where manual order
  is the ordering — a board's columns and the Inbox — and not to saved views, which
  impose orderings of their own.
- **Reminders** — `UserDefaults`, keys `SimpleKanbanRemindersEnabled`,
  `SimpleKanbanReminderHour`, `SimpleKanbanReminderMinute`, owned by
  `NotificationScheduler` rather than read by the view. The scheduler has to *act*
  on a change — moving the time of day moves every pending request — so the switch
  and the picker bind to `NotificationScheduler.shared` and it writes the defaults
  itself. A second copy in `@AppStorage` would set the preference and reschedule
  nothing.
- **The accent stays in `BoardSnapshot`.** Moving it would be a v7 migration whose
  only job is to copy one field into `UserDefaults`, and the migration runs inside
  `BoardFile.decode` off the main actor, where reaching for app-global state would
  make the same bytes decode differently on two machines. It is also the one of
  these that reads naturally as board data: a board restored from a backup comes
  back looking the way it did. So it is left where it is, deliberately and whole —
  and an import or a restore never adopts the arriving file's accent, which is what
  keeps "it travels" from being true of it in practice.
- **The dozen in `Preferences.swift`** — gathered rather than scattered, which is
  a deliberate departure from the four above. One preference reads best beside
  the thing it configures; twelve arriving together read best in one file, where
  the question "what can be set, and what is the default" has one answer. Each is
  an enum rather than a raw number, so the default is written once, the row has a
  label, and an out-of-range value cannot be stored. An "off" state is a case —
  `AutoArchive.never`, `WeekMeaning.rollingSevenDays` — because a preference
  whose off state is an absent key reads differently on a fresh install than
  after it has been turned off again.

  | setting | what it changes | default |
  | --- | --- | --- |
  | New tasks are due | `mintTask`, through `BoardStore.defaultDueDate` | no date |
  | Archive finished cards | `sweepDone(now:after:)` | never |
  | A week means | `SavedView.dueThisWeek` and the weekly figures | the rolling seven days |
  | Card detail | `BoardTaskCard` | comfortable |
  | Tick cards off from the board | `BoardTaskCard`, `PhoneTaskCard` | off |
  | App icon | `AppIcon.resolve(_:themes:appearance:)` through `AppIconInstaller` | `4f`, peach → violet |
  | Icon follows app theme | the same, resolved against the theme in the slot on show | off |
  | Reopen the view I was on | `applyStoredPreferences()` | off |
  | Open the Inbox with the board unless it's empty | `raiseInboxWithTheBoard()`, on every arrival at the board, and not on the phone | off |
  | The Trash keeps things for | `TrashedItem.isExpired(at:days:)` | 30 days |
  | Backups to keep | `backupNow(keeping:)` | 25 |
  | Also remind me the day before | a second `TaskReminder` per card | off |
  | Tell me daily while anything is overdue | one repeating request | off |
  | Open at login · Show the menu bar item | `SMAppService`, `MenuBarExtra(isInserted:)` | off · on |

  **The checklist is two things on a card, in two registers.** The fraction —
  `SubtaskCountBadge`, "2/3" behind a checklist glyph — sits against the meta
  row's **trailing** edge, and a line runs the width of the card's foot, filled
  to the same share. The number is for reading one card; the line is for reading
  a column of them without stopping at any.

  The fraction was third from the left until it moved, where the priority dot
  and the due chip — neither of which is always drawn — pushed it a different
  distance in on every card, so a column of counts ran down a ragged diagonal.
  Against the trailing edge they line up, and the pair reads as one thing: the
  fraction with the line directly beneath it.

  The line is drawn *inside* the card's own rounded rectangle and clipped by it,
  in the same `ZStack` the card's ground is, so its ends follow the corners
  instead of squaring them off and the shadow underneath is the card's rather
  than a bar's hanging off its foot. `ProgressMeter` gained an `isFlush` for it:
  square ends where something else's corners are already doing the shaping, and
  the capsule everywhere it floats in a row with air either side — the
  inspector's checklist header, the week meter. And it is drawn **whatever the
  density is**, unlike the fraction: compact exists to buy back vertical space,
  and the line is the one thing on a card that costs none, so the mode chosen
  for reading many cards at once is the one that keeps it. It is decoration and
  hidden from a reader; the fraction says the same in words and is what the
  card's combined label carries. `CardProgressTests` holds all of that.

  **What a card shows** is two of those rows. *Card detail* drops the
  description and the meta chips; **Tick cards off from the board** takes away
  the circle in a card's trailing gutter — `Preferences.cardTickKey`, read as
  `@AppStorage` by `BoardTaskCard` and `PhoneTaskCard` alike so every card on
  the board closes up the moment it is flipped. It is the only switch here whose
  state takes a *verb* off a surface, which is exactly why it is a preference
  rather than a decision: the circle is the fastest way to finish something and
  the easiest thing to catch with a thumb on a board being dragged around, and
  which of those matters more is not a question this app can answer for
  somebody.

  **It arrives off**, because the accident is the expensive half of that trade.
  A card ticked by a thumb that meant to pick it up is not a stray glyph: it
  chimes, it may auto-archive, and it has to be found again to be undone. A card
  that cannot be ticked from the board costs one press of this switch, by
  somebody who has already decided they want it. Everything else in **What a
  card shows** is the same card either way, and the two routes that finish a
  card without the circle — the context menu and the detail panel's own tick —
  are drawn whatever this says.

  **The circle is in the trailing corner**, and it moved there from the leading
  one, where it stood in front of everything a card has to say: the label chips
  and the title both start there, and the gutter it needed pushed them in by a
  tick's width on every card whether or not that card was near being finished.
  The trailing corner is where the rest of a card's furniture already is — the
  sub-task count sits under it, and on an archived card the Restore button below
  that. Both cards ask one rule for whether to draw it at all,
  `BoardTaskCard.drawsToggle(isArchived:showsCardTick:)`, so the phone and the
  desk cannot disagree about a card that is filed away; `CardCornerTests` is
  that rule and the corner it is drawn in.

  The gutter is held by a single `Color.clear` spacer in `content`, so switching
  it off shifts the card's text out to the card's own margin rather than leaving
  a hole where the circle was — the same closing-up an archived card has always
  done, now with a second reason to ask for it. The phone pays its leading
  margin back explicitly: the 5pt inset there is the *gutter's*, because a 44pt
  square overhangs the 22pt circle it draws by 11 either side, so with no gutter
  `PhoneTaskCard` owes its text the 15 its trailing edge already pays. Neither
  card silences the Archive's Restore, which uses the same gutter for the one
  verb a filed card has. What is left to finish a card with: its context menu,
  ⌘↩ and the Task menu on the desk, and the detail surface's own tick — in the
  panel's header on the desk and the iPad, beside the title on the phone — which
  is drawn whatever this says. See **Completing, reopening and deleting**.

  **Where a launch lands** is `BoardStore.landingSurface`, and it is not the same
  answer everywhere. The **desk and the iPad open on the board**, because on
  those the board is not a destination — the source list, the board and the
  inspector are all one window, and a saved view standing in front of it would be
  hiding something rather than answering with it. The **phone opens on Today**:
  it shows one place at a time, and the app is opened to answer one question —
  what is there to do now. Landing on a board answers "which column was I
  scrolled to", which is a question about the app rather than about the work, and
  the board is one tap away on the bar underneath. The split is on the *idiom*
  rather than on `#if os(iOS)`, because iPadOS is iOS and is not the phone;
  `RootSurface` needs the size class as well to pick a layout, but this is only
  choosing where to land, and an iPad in Slide Over is still an iPad.

  Two things follow from that, and both were bugs waiting to happen. **The board
  is written down now**, as `"board"` in `lastSurfaceKey`, where it used to clear
  the key — sound while every launch landed on the board, since "nothing stored"
  and "the board" were the same answer, and wrong the moment they became two:
  somebody who asked to be put back where they were would have been put on Today
  instead. And **"Open the Inbox with the board unless it's empty" is honoured on
  the board only**, which is what it says: the phone's Inbox is a sheet drawn over
  whatever is there, so an unconditional raise would put the panel over Today and
  hide the very thing the launch went to.

  Two further conditions on the same line, and each is on the same split the
  landing surface is. **The switch is the desk's and the iPad's**, through
  `BoardStore.inboxOpensBesideTheBoard`, which Settings asks before it draws the
  row at all: on those two the Inbox stands *beside* the board and opening it
  with the board adds a column to a window that still shows everything it showed
  before, while on the phone the same setting would read "cover the board at
  launch". The idiom again rather than the size class, for the reason above. And
  **an empty Inbox stays shut** — a panel raised over nothing is a column of
  blank taking width from the board to say "no", which the count on the sidebar
  row says already without moving anything.

  **It is a standing rule and not a thing that happened at launch.** All four
  conditions live in `raiseInboxWithTheBoard()`, and the launch is only its first
  caller. The sentence is about *arriving at the board*, and picking another
  board or coming back from Today is arriving at the board — so the panel comes
  back on each of those, and shutting it answers for the board in front of you
  rather than turning the setting off for the rest of the session. The rule sits
  in two places because there are two kinds of arrival: `surface`'s `didSet`
  catches every route back to the board — the sidebar, the View menu, the tab
  bar, `activeView`'s setter — and `selectBoard(_:)` asks for itself, because
  board-to-board leaves `surface` at `.board` on both sides and the observer
  never runs. It **only ever opens**: an empty Inbox is a reason not to raise a
  panel, never a reason to take away one already standing, or dragging the last
  card out of the Inbox would close the panel it was dragged from.

  The one gap is the awaiting-sync path, where a card that lands seconds after
  the launch leaves the panel shut until the next arrival at the board — a panel
  that opened itself some while after the launch would be the worse of the two.
  And because the value is carried on the store for `trashRetention`'s reason,
  the Settings row writes it *through* to `BoardStore.opensInboxWithTheBoard` as
  well as to the defaults; without that the store would go on answering with
  what was read at launch and a switch flipped in Settings would do nothing until
  the app was quit.

  `applyStoredPreferences()` runs on the `restored(…)` path alone, so a store
  built any other way — a test, a preview — is untouched by any of it. The DEBUG
  launch overrides moved to the end of it from the end of `init`, which is where
  they have to be: `-SimpleKanbanTab board` set the board and the stored
  preferences then put Today back over it. A launch argument is a person at a
  terminal saying where to open, and it beats what was stored.

  **What each one *changes* is carried on `BoardStore`, not read from the global
  at each use** — `trashRetention`, `defaultDueDate`, `weekMeaning` are
  properties there, seeded from `Preferences` when the store is made. That keeps
  the hot paths off `UserDefaults`, and it is what makes them testable: Swift
  Testing runs suites in parallel, so a global swapped for the length of one
  test is a global every other suite reads mid-swap. The first version of
  `PreferenceBehaviourTests` did exactly that and crashed the test host inside
  `SearchScopingTests`, several suites away and with nothing in the failure to
  say why. `Preferences.reading(_:)` is the narrow exception, for the tests that
  are checking the *reading* rather than the behaviour.
- **`sweepDone` is not undoable, and neither is `sweepTrash`.** Both are a
  promise being kept rather than something the user did, and a ⌘Z that reached
  either would be undoing the passage of time. `sweepDone` measures on
  `updatedAt`, which is when the card last moved — so a finished card that is
  still being edited is not archived out from under the person editing it.
- **The overdue notice is one repeating request, not one per card.** A nag that
  arrives five times says nothing the first one did not, and the 64-request cap
  the system imposes is not worth spending on repetition. It is diffed on the
  *count* rather than held in `desired`/`published` with the per-task reminders:
  it repeats, it names a number rather than a card, and it exists or does not
  exist. Removing it unconditionally on every flush — the first version — put a
  removal in the log on every save and broke nine notification tests that assert
  a quiet centre.
- **Default column for new tasks and WIP limits are not there.** Both are fields on
  `Board`/`BoardColumn` — board data, and so a schema change and a migration — and
  putting either in `UserDefaults` is exactly the mistake the rule above is about.

### Export and import

`.simplekanban` is a JSON document declared by the bundle
(`UTExportedTypeDeclarations` and `CFBundleDocumentTypes` in `project.yml`,
`UTType.simpleKanbanBoard` in code) and written through `BoardFile.encoder()` — the
same encoder `board.json` is written with, so an export and a board file are one
format: a `board.json` copied off another machine imports directly, and an export
can be dropped in as a board file. There is a Markdown export beside it, export
only: it is lossy — ids, timestamps and activity all go — and a round trip through
it would quietly discard the history the JSON keeps.

**An import merges. It never replaces, and it never picks a winner.**

- **Tasks match on `id`** — which is the reason 3.7 moved ids to UUIDs before there
  was anything to link them. Byte-identical: skipped, so re-importing the same file
  is a no-op and leaves no ⌘Z behind. Same id, different card: **both are kept**,
  the arriving one under a fresh id. A card that is already here in every respect
  but its id and its code — the copy an earlier import made — is recognised and
  skipped, so re-importing a file that collided does not grow the board again.
- **Codes are re-minted only where they would collide.** A code is a label somebody
  may have pasted into a commit message; nothing already here is renumbered.
- **Boards match on `id`.** One already here keeps its name, dot and prefix and
  gains only the columns it is missing: a board is an arrangement the user made. A
  new board arrives whole, with any column id already in use re-minted — column ids
  are unique across boards because the store resolves a card's board from its
  column.
- **Labels match on `key`**, and the definition already here wins: taking the
  arriving file's word for `design` would rename every chip on the importing
  board's cards.
- **The accent and the active board are not the file's to change.**
- One undo step, named "Import Board", and the tasks go back through
  `BoardStore.placed` on the way in, so a card naming a column that did not come
  with the file lands in the Inbox rather than nowhere.

**Three doors hand the app a file** — the import panel, a `.simplekanban`
double-clicked in the Finder, and the same tapped in Files — and all three go
through `SettingsNotice.importing(_:into:)`, so all three claim the sandbox's
security scope (`BoardImportFile.read`), merge by the same rule, and *say what
happened*. An import that changed nothing says so; one that failed says the board
was not touched. The opened-file branch exists because the bundle claims the
document type: without it the user's own board file arrived at the deep-link
parser and was told it was not a task link, which is the worst answer available.
`LSSupportsOpeningDocumentsInPlace` is `true` in `project.yml` — the file is read
and merged, never edited where it lies, so a copy into the app's Inbox would be
litter nothing here deletes.

File ▸ Import… and Export… are live on macOS and drive the same panels through
`store.isImportingBoard` / `store.isExportingBoard`. `BoardTransfer` is attached
by whichever surface *raised* a panel rather than once at the root: on iOS the
settings sheet is already presented over the root and a `fileImporter` underneath
it has nowhere to appear, and on macOS the menu bar belongs to the window, so its
panel should sheet onto the window rather than onto the Settings pane. Nothing is
`source: .unbuilt` any more; the case stays in `AppCommandSource` so the next
unbuilt command is declared rather than omitted.

The macOS build is sandboxed, so `Resources/SimpleKanban.entitlements` grants
`com.apple.security.files.user-selected.read-write` (it was read-only, which is
enough to open a file and not to save one). `build.sh --sign` reads the
entitlements back off the built binary, drops `get-task-allow` and re-applies them,
so the widened grant needs nothing from the script.

### Restoring a backup

`BoardFile.restore(from:)` shipped with the rolling backups in 1.21 and had no
caller until now. Settings ▸ Data lists `backups()` newest first with the moment
each was taken, and a restore is **an edit to the board, not a file move**: one undo
step named "Restore Backup", through the same `apply` an undo uses, so the caches
and any open editing session are tidied by the code that knows how.

Before it lands, the board as it stands is written and copied into `backups/` by
`BoardFile.backupNow()` — the forced counterpart to `backupIfDue`, which
deliberately will not take two in one second. A restore is the one action that
leaves the current board reachable only through the undo stack, and an undo stack
does not survive a quit. If that copy cannot be taken the restore still happens and
`lastError` says so; it is a courtesy, not a gate.

Nothing here defeats Phase A's per-URL write ordering, which exists for exactly
this: `scheduleSave()` claims its generation when the restore is queued, so a
debounced write armed before it is by definition older and is dropped rather than
silently putting the damaged board back. **Delete everything…** takes the
same forced backup and is undoable the same way.

## System integration

Four things outside the app can now reach a task, and one thing inside it can
reach the system. All of them hang off two files — `Sources/Store/NotificationScheduler.swift`
and `Sources/Model/TaskIntents.swift` — and all of them are joined to the app in
five lines, which `SystemWiringTests` reads out of the source and asserts, because
a scene has nothing to enumerate at runtime and a modifier commented out of a
`body` is invisible to everything else.

### Due-date reminders

One local notification per task that has a due date, at a time of day the user
picks. `BoardStore.scheduleSave()` is the hook — **not** the four mutations that
touch a due date. Every mutation already comes through that funnel, including the
bulk commands, a drag into Done, `archiveCompleted`, and undo and redo, and a
per-call-site hook misses all of them silently. It sits *below* the `guard let
file` so an in-memory store — a test, a preview — can never reach the machine's
Notification Centre. Both `NotificationScheduler.reconcile` and
`TaskSpotlightIndex.reconcile` diff against what they last published, so a
keystroke that changes no due date sends nothing.

`BoardFile.isRunningTests` gates both reconciles, and this is not belt and
braces: `xcodebuild test` launches the app as the test host under its real bundle
identifier, and most suites here are **file-backed** — `TempBoard` hands out a
throwaway `BoardFile`, not a `nil` one — so "an in-memory store is a test" does
not cover them. Without the gate a suite run indexes `TestBoard` into the
developer's Spotlight. `BoardFile` already steps `.default` aside for exactly the
same reason; `SystemWiringTests` asserts the detection still fires.

**Authorisation is asked for by the diff, not by a call site.** Not at launch: a
permission prompt on first run, before the user has set a due date or seen the
board, is how an app gets denied permanently. It is asked the first time a
reminder *appears* that was not there a moment ago, and only while the answer is
still `.notDetermined`. `hasBaseline` is what stops the due dates already on the
board at launch counting as an appearance — remove it and the app prompts on first
run and is denied for good.

`desired` and `published` are deliberately separate. With permission missing,
`published` is emptied so revoking in System Settings does not leave a week of
stale requests queued, while `desired` keeps what the board wants — which is what
lets granting permission later republish the lot without the board changing again.
Only the 64 soonest are scheduled: `UNUserNotificationCenter` holds 64 pending
requests and drops the rest without saying which, so `reconcile` sorts by fire
date and caps. `TaskNotificationCenter.add` is synchronous because
`UNNotificationRequest` is not `Sendable` and an `async` version cannot be handed
one from the main actor at all.

The identifier is the task's UUID, so a reschedule is an add and a cancel is a
removal, and both are idempotent. A refusal is a standing condition rather than an
error to report once, so it is stated beside the switch it has silenced, with a
button to System Settings — asking a second time returns `false` without showing
the user anything.

### Deep links, Handoff and Spotlight

`simplekanban://task/<uuid>`. The uuid and not the `code`: a code is minted per
board, is not unique across installs, and is the half a person retypes. `TaskLink`
parses strictly, so a URL that is not one of ours is never mistaken for a task
that has gone away.

Four doors arrive at one place. `DeepLinkRouter` is a queue of one, because a link
can arrive before the scene exists — a notification tapped from the lock screen
launches the app and the delegate runs while the window is still being built — and
`.systemEntryPoints()` carries all four: `onOpenURL`, the Handoff activity, the
Spotlight action type, and a resolve on appear for whatever was already waiting.
It goes **inside `RootView.body`**, not on `root`: it reads the store out of the
environment, and a modifier applied after `.environment(store)` sits above it in
the tree and would never see one.

A link that names nothing has to say so — doing nothing is indistinguishable from
the app having failed to launch, and leaves the user re-clicking. There are two
alerts, on separate channels: `failure` for a link, `notice` for an opened file.
Revealing a task clears the query first, because a link landing on a board
filtered to something the task does not match opens onto an empty column, which
reads as the link having failed. `reveal` raises **every** detail surface the app has
rather than the one this platform was assumed to have: `isInspectorOpen` on both,
and on iOS also `sheetID`, the column, the tab and closing the drawer. The two do
not collide — the phone has no inspector and the iPad presents no sheet, and each
surface reads only the state it has. It used to branch `#if os(iOS)` straight
into the phone's state, so on an iPad a `simplekanban://` link, a notification
tap, a Handoff or a Spotlight hit selected the task and then showed **nothing at
all** whenever the panel was closed. An archived task opens the Archive and skips
the tab move.

Handoff and Spotlight publish from whichever surface is showing a task:
`.taskUserActivity(task)` on `TaskInspector` and on `PhoneDetailSheet`. Spotlight
is keyed on `updatedAt`, so a mutation that does not stamp the task — `archive`,
`unarchive` — does not re-index; that is correct, because the `!task.isArchived`
filter removes an archived task from the index and unarchiving re-adds it under a
stamp the index has never seen. **Copy Link** is on both cards' context menus and
puts the URL on the pasteboard; ⌘C still copies the card itself, so the two are
separate verbs rather than two representations of one.

### App Intents and the menu bar extra

`AddTaskIntent` (title, optional board, optional column, optional due date) and
`ShowTodayIntent`, with `BoardEntity` and `ColumnEntity` queries so Shortcuts
offers the boards and columns that actually exist. `AppShortcut` collides with the
app's own `AppShortcut` in `AppCommand.swift`, so every use is written
`AppIntents.AppShortcut` — do not "simplify" it.

**Those two live in `TaskIntents.swift`; the rest are in
`TaskActionIntents.swift`.** The split is by subject rather than by size: the
first file is the app's *doors* — deep links, Handoff, Spotlight, the bridge —
and the second is its automation vocabulary. What the second adds is Complete,
Reopen, Move, Open, Find Tasks, Get Tasks in View, Set Due Date, Set Priority
and Change Label.

**`TaskEntity` is what makes all of them usable.** Without it each would take a
raw UUID, which is not a thing anybody has: a Shortcut is built by picking a card
from a list or finding one by name. Its query is an `EntityStringQuery` running
the app's own search through `BoardStore.tasks(matching:)`, so a card is found by
title *or* by code — "NW-118" is what a person says out loud — with the same
folding the search panel does. It suggests the Inbox and the active board rather
than every card in the file: a picker of four hundred rows is a picker nobody
scrolls, and the string query is how the rest are reached.
`BoardStore.tasks(matching:)` exists rather than `narrowed(_:)` because
`narrowed` reads `query`, the field the user is typing in — an intent must not
answer somebody's half-typed search, nor rewrite it to run its own.

`ViewEntity` and `LabelEntity` are the same shape for saved views and labels. The
view one is deliberately **not** the widget extension's `WidgetViewEntity`: that
is configured in another process against a digest, this one reads the live store,
and sharing the type would mean sharing a data source neither half can hold. The
priority parameter is a `TaskPriorityAppEnum` rather than `Priority: AppEnum`,
because `Priority` is compiled into the widget extension too and conforming it
would put an automation vocabulary into a bundle that draws a coloured dot.

Three rules the verbs share:

- **Nothing silently does nothing.** A card deleted since the Shortcut was built
  is the likeliest failure of any of this, and a shortcut that "worked" while
  doing nothing is indistinguishable from one that ran. Each names its own kind
  of missing thing — `noSuchTask`, `noSuchView`, `noSuchLabel` — which is
  `DeepLinkFailure`'s rule spelled for Shortcuts.
- **Completing something already done is not an error.** A Shortcut that runs
  nightly over everything overdue would fail on its second run, and "it is
  finished" is what the caller asked for either way. `cannotComplete` is kept for
  the case that genuinely cannot happen: a board with no Done column.
- **Add means add.** `ChangeLabelIntent` takes a direction rather than
  toggling, because a rule saying *put the Urgent label on this* must mean that
  whether or not the label is there — a Shortcut run twice must not undo itself.

Only **Complete** joins Add Task and Show Today in `SimpleKanbanShortcuts`.
Registration buys a *spoken* phrase, and every other verb needs a card named
first, which is not a thing anybody says to Siri; all of them are reachable from
the Shortcuts editor regardless. `OpenTaskIntent` is the one with
`openAppWhenRun = true`, for `ShowTodayIntent`'s reason — it is navigation — and
it goes through `BoardStore.reveal`, the same call a deep link and a tapped
notification make.

`AddTaskIntent` has `openAppWhenRun = false` and therefore depends entirely on the
store being registered before any scene exists: `SimpleKanbanApp.init()` builds it
and calls `TaskIntentBridge.adopt(store)`. On `.onAppear` instead, a cold launch
driven by an intent would perform before the first render and fail with "still
starting up". `SystemWiringTests` asserts both the call and its position.
`ShowTodayIntent` is `openAppWhenRun = true` because it is navigation.

**⌃⌘N was not built as a global hotkey, deliberately.** A true system-wide key
needs Carbon `RegisterEventHotKey` — a C callback and global mutable registration
under Swift 6 strict concurrency — or the Accessibility permission, which is a
very large thing to ask for a text field in a notarized sandboxed build. What
shipped instead is a `MenuBarExtra` (one field, a persisted destination picker, a
confirmation line, "Open Board") plus the existing in-app ⌘N — and `AddTaskIntent`
in the Shortcuts app, which will bind a system-wide key press to it, ⌃⌘N included,
at no permission cost and maintained by Apple.

The quick-add default destination is the **Inbox**, not Up Next: a capture made
from another app is precisely the case the Inbox exists for, and deciding which
board it belongs on is the thing the user is deferring by capturing at all. The
picker offers every column of every board and remembers the choice; a remembered
column that has since been deleted falls back to the Inbox rather than erroring.

### The share sheet

`SimpleKanbanShare` is an app extension on **both** platforms: text or a link
shared from any app becomes an Inbox card. It is the phone's equivalent of the
desk's menu bar quick add, and on the desk it is what puts Simple Kanban in
Safari's Share menu.

**The extension writes one file and does nothing else.** It never opens
`board.json` and never opens the record store. The board file is versioned,
migrated on the way in, quarantined when it cannot be read, and is the only copy
of the user's work — none of which is safe to hand to a process the system
starts and kills around a share sheet. What crosses instead is a
`PendingCapture`: a title, a note, a timestamp, written into `Captures/` in the
App Group, beside the `Widgets/` folder the digest lives in. This is the write
side of the fence **The widgets are handed answers, not the board** describes
from the read side.

**One file per capture, not one file appended to.** Two share sheets in quick
succession are two processes, and a read-modify-write of a shared list across
two processes loses one of them — there is no lock either side could take that
the other is guaranteed to respect. A file each has no race at all.

**A capture is not a cache, and that is where it parts company with the
digest.** A digest that will not decode is refused and forgotten, because the
app rewrites it within half a second. A capture is the only copy of something
somebody typed, so one the app cannot read is *set aside* — renamed to
`.rejected`, still on disk — rather than deleted, which would be silent loss, or
retried, which would fail on every launch for the rest of the install's life.
The board file's quarantine rule, applied to something much smaller.

`BoardStore.adoptPendingCaptures()` drains the folder, on `.onAppear` and on
every `scenePhase == .active`. Both are needed: a launch is not a foregrounding
on either platform — the scene comes up already active and the change never
fires — so the first catches whatever was shared while the app was not running
and the second catches everything after. N shares are **one** ⌘Z, the way a
paste of N lines is. **A file is deleted only once its card exists**, in that
order: a crash in between costs a card that arrives twice, which the user can
delete, where the other order costs one that never arrives at all, which they
cannot get back and would have no way of knowing about.

**There is a sheet, and the title is editable.** A no-UI extension is one tap
faster and gets the title wrong constantly — shared pages are called
"Home | Acme Corp — Official Site" and shared selections start mid-sentence.
The first non-empty line of the shared text is the title and everything else is
the note; a bare link names itself by its host with `www.` dropped, with the
whole address still in the note; a title too long to read in a column is cut at
a word boundary and **kept whole at the top of the note** — nothing is dropped,
it moves. `CaptureDraft.from(text:url:)` is a free function of two optionals
precisely so those rules can be tested, because no test in this suite can
present a share sheet or drive an `NSItemProvider`.

The sheet wears the user's theme by reading the widgets' digest, which is
already in the group and already carries `themes` and `appearance` — no board is
opened to get it, and with no digest yet it falls back to the shipping preset,
which is what a widget draws in the same position. A write that fails leaves the
sheet open with the user's text still in it and says why: there is nowhere here
to retry to, and the one thing that must not happen is pretending it worked.

**What no test can reach.** The share sheet itself, on either platform. What is
pinned instead is everything either side of it: the draft rules, the folder, the
drain, and — in `PackagingTests` — that the `.appex` is embedded and declares
the right extension point, principal class and activation rule, each of which
fails silently in its own way. Two things need a person:

- **iOS** — share a page from Safari, confirm the card appears in the Inbox when
  the app next comes forward.
- **macOS** — the extension only appears once Launch Services has seen the
  containing app: the app in `/Applications`, run once, then enabled in
  System Settings ▸ Extensions ▸ Sharing. A build run out of `build/` may not
  show up at all, and that is not a bug in the code.

Both bundle identifiers — `com.n14395.SimpleKanban.Share` on each platform —
need App IDs with the App Group capability. Automatic signing with
`-allowProvisioningUpdates` mints them the way it did for the widgets, but the
first build of this target needs the network and the team.

### Comments were considered and not built

The seed entry that implied them ("Comment added on spacing") was removed in
Phase A. If comments ever exist they must be a **first-class type separate from
`ActivityEntry`** — a comment is authored content the user writes and can edit and
delete, activity is a system log nothing may rewrite, and conflating them means
either an activity feed the user can edit or comments the user cannot. The reason
not to build them now is that this is a single-user local app with no sync (6.4 is
explicitly out of scope), so a comment has no second reader: it is a note addressed
to nobody, and `TaskItem.note` plus sub-tasks already carry everything a
note-to-self needs. Real commenting becomes a feature once there is someone to
comment *to*, which means after sync. So: no `Comment` type, no UI, and if it is
ever revisited it starts as its own array on `TaskItem` with its own snapshot
version bump — never as a case on `ActivityEntry.Kind`.

## Widgets

Four widgets, on **macOS and iPadOS** — and on the phone too, because a widget
extension that supports iOS supports every iOS device and refusing to draw on
one would be a worse answer than drawing. They are a target of their own,
`SimpleKanbanWidgets`, embedded in the app.

| Widget | Sizes | Shows | Configured with |
| --- | --- | --- | --- |
| **Inbox** | small, medium, large | small: the `+` and how much is waiting. medium: the `+` beside the first four. large: the list, with the `+` in the corner | nothing — there is one Inbox |
| **Saved view** | medium, large | medium: the view's name and glyph on the left, the top four as bullets beside it. large: the list, with due chips | which saved view |
| **Column** | medium, large | the cards in one column, under the board's name — the top four, or the top seven | which column |
| **Board overview** | medium | every column *before* Done, its name and its count | which board |

Every row is a link to its card, every heading opens the list it names, and the
`+` opens the app's own capture with the keyboard in it.

Where a widget has more than one size it is **the same widget with more room**
rather than a different one: the Inbox and Column widgets keep their heading and
gain rows as they grow, because somebody who resizes one should get more of what
they had. The saved-view widget is the exception, and deliberately — its medium
tile is a glance (*is there anything I should know about*) and its large tile is
the list itself (*what am I doing today*), which are different questions. A
column widget keeps its due chips at both sizes: a column is where a date means
something, and the bullet treatment would drop the half of a card it is read
for.

**The board overview leaves Done off**, and reads it off position rather than
off the word — `WidgetBoard.workingColumns`, which is `Board.workingColumns`
again, so a Done column renamed to *Published* is still the one that goes. It is
the one column that only grows, so on any board older than a fortnight it is the
largest number on the tile and the least interesting: a glance at a board is a
glance at what is *left*. The heading's count is the working columns' too, so
the tiles add up to the number above them, and anybody who does want to watch
Done can point a column widget at it — which is why the filtering is at that one
point of use and not in the digest. A board holding nothing but its Done column
says so rather than drawing an empty row.

### The widgets are handed answers, not the board

`Sources/Widgets/WidgetDigest.swift` is the whole of the contract between the two
targets: a flat, capped rendering of exactly what the widgets draw — the rows,
already filtered, already sorted, already cut to eight — beside the counts the
app computed for the badges.

**The extension evaluates nothing.** A saved view is a rule tree over every task
in the file, a column's contents depend on the board's sort order and on which
cards are archived, and *is this card done* is a question about the board's last
column rather than a field on the card. All of that already exists, once, in
`BoardStore`. A second implementation living in an extension would be a second
implementation *diverging* in an extension — where nobody would see it, because a
widget that quietly disagrees with the app looks exactly like a widget that has
not refreshed yet.

Two things that are not answers cross as well. `themes` is the app's own
`ThemeSettings` verbatim, so a widget wears the theme that was chosen — a custom
one included — rather than an approximation of it; and `today` is the day the
lists were evaluated against, so a due chip in a widget says what the same chip
says on the board. A widget reading the clock itself would draw yesterday's list
against today's date for one refresh.

It is **not** `board.json`. That file is versioned, migrated on the way in, and
the only copy of the user's work — three good reasons not to hand a read of it to
a process that runs on the system's schedule rather than the user's. It also
decides what happens when the two sides disagree about a format: a digest whose
`version` is not this build's is *refused*, never migrated, because the app
rewrites it within half a second of the next edit and the cost of refusing is a
widget drawing its sample for that half-second. The cost of reading one written
by a build that meant something else by these fields is a widget quietly showing
the wrong numbers.

The one number that is deliberately not `tasks.count`: a saved view's pill is the
view's own count, capped by the view's own `limit`. *Recently updated* stops at
twenty and the digest carries eight of them, and those two caps mean different
things.

### What writes it

`WidgetPublisher` is the **fourth follower a save carries**, beside the reminders,
the Spotlight index and the synced records — see `BoardStore.reconcileSystemsAndSync`.
It rides the same debounce for the same reason: it is O(board), and a burst of
keystrokes should pay it once. `BoardFile.isRunningTests` gates it exactly as it
gates the other two, and for the same reason — a suite run would otherwise publish
its fixtures to the developer's own widgets.

It reconciles against what it last wrote before waking anything. A board is saved
on every keystroke of a title and on every drag of a card, and most of those
change no count, no order and no row inside the first eight; `reloadAllTimelines`
on each of them would be the app asking the system to re-render four widgets a
character. The stamp is set aside for that comparison, being the one field that
differs on every pass by construction.

Two moments are not saves, and `WidgetKeeper` covers them from `RootView` —
where the store, the clock and the appearance override can all be read at once,
which is the same reason `AppIconKeeper` is a view modifier:

- **A launch**, because nothing has been saved yet and a machine rebooted with a
  widget on the desktop would draw the digest from before the last quit.
- **Midnight**, because *Today* and *Due this week* are answers about a day and
  the day rolls over under a board nobody is editing. `DayClock` is what knows.

The widgets' own timelines reload just after midnight too, so the chips roll over
on a machine where the app is not running at all.

### The App Group

`WidgetShare.appGroup`, and it is **spelled differently on each platform**: a
sandboxed macOS app may only join a group whose identifier begins with its team
identifier, and iOS rejects that spelling in provisioning. Five entitlement files
carry it — the app's three and the extension's two — and `WidgetShareTests` reads
them off disk and holds them to the constant the code calls `containerURL(for:)`
with. There is no runtime value that could state this: the extension is another
process, and the app's own entitlements say nothing about it.

A build that is **not** entitled to the group is not a crash. `WidgetShare.container`
is `nil`, the app publishes nothing, and the widgets draw `WidgetDigest.sample` —
which is also what the gallery shows before a widget has been placed, and what a
fresh install shows before the app has been opened.

### Links

`AppLink` is the vocabulary: `simplekanban://` plus a task, a board, a column, a
view, the Inbox, or a new capture. The app has answered the first since links
existed — `TaskLink` now delegates to it — and the other five are what a widget
taps into. They are one type rather than five call sites building strings because
the extension *writes* these URLs and the app reads them, from different targets:
a shape that drifted would be a widget whose taps do nothing.

A column link carries the column's id and not its board's, so a column moved to
another board keeps working and lands on the board it is on *now*. A host with
anything after it — `simplekanban://inbox/…` — is refused rather than read as the
bare host, so a destination a later version might mean by it cannot be silently
swallowed.

Each of the four things a widget can be configured with is deletable while the
widget goes on naming it, so each has its **own** sentence when it has gone:
"That view no longer exists" tells somebody which widget to fix, where a shared
"something went wrong" does not.

**Widgets link; they do not act.** WidgetKit will run an `AppIntent` in the
background from a button, and for *add a task* that is exactly the wrong thing —
a task added with no title and no way to type one is litter the user then has to
find and delete. The `+` opens the app on a fresh Inbox capture instead.

**And it opens the app's own capture rather than a third thing.** That control
is genuinely different on each platform — the Inbox panel's one-line composer
where the Inbox is a panel, the card's whole editor in a sheet on the phone,
where there is no panel to put a composer in — and reaching for something in
between is what did not work. The first version made the card itself and opened
it in the task editor, which is right on the phone, because a sheet is
*presented*; the iPad's editor is a column of the split view, and a
`@FocusState` assignment aimed into it is refused outright. Measured on an iPad
Pro 11": twenty attempts over a second and a half, the field reporting `nil`
focus after every one. What the user saw was a panel on the right card with an
empty title, no caret, and the first thing typed going nowhere — plus, because
the editor was competing with the Inbox panel for a width that does not hold
both, sometimes no editor at all. `simplekanban://new` now calls exactly what
the toolbar's `+` calls, and `BoardStore.inboxOpensBesideTheBoard` is what picks
between the two. What happens *after* the title is typed is the iPad's own rule
— see **A card made here opens in the editor** — so the widget's capture ends in
the editor there without this path knowing anything about it.

### Drawing them

The extension compiles `Sources/Theme/` and four model types — `CalendarDay`,
`DueDate`, `Priority` and `TaskLabel` — so a widget's colours come out of the
same `Palette` the board's do, through the same `ThemeGradient`, `dueTone` and
`priorityColor`. Which of the two theme slots is *not* the widget's decision
alone: the system hands the extension a colour scheme, and that is the answer
whenever Settings ▸ Appearance is on **System** — but somebody who has pinned the
app to Dark has pinned the app, and a widget that went light at sunrise would be
the only part of it that did. `AppAppearance.slot(under:)` reconciles the two and
is the same expression `RootView` builds its palette from; the enum moved out of
`SettingsView.swift` into `Theme/` so both targets can see it.

`Resources/Fonts` is in the extension's target as well as the app's, because
`FontCatalog` registers what it finds in `Bundle.main` and inside an extension
that is the extension. Without them a widget wearing Spectral draws in the system
serif, which is the one difference a person notices at a glance.

The board overview's tiles carry the column's **full name over two lines**
rather than `BoardColumn.short` on one. That abbreviation exists for the "move
to" control, where the room is a segment of a segmented control and there is
exactly one line of it; there is more room than that here, and "In Progress"
wrapped over two lines beats "Doing". `lineLimit(2, reservesSpace: true)` is
what keeps the row even — without it a tile whose name fits on one line is
shorter than its neighbours, and the height would change when a column is
renamed.

Row counts are **fixed** per family — four on medium, seven on large — rather
than measured with `ViewThatFits`. Measuring sounds better and is not: the answer
then changes with the type size, so the same widget shows five rows on one machine
and seven on another, and the list a person reads every morning is a different
length each time they change a setting somewhere else.

The extension's own code lives under `Sources/WidgetExtension/` and is excluded
from the app's target in `project.yml`. It is under `Sources/` rather than beside
it so that the suite's source-tree rules — no unlocalised prose, no
`Text(verbatim:)` carrying words — apply to it like everything else.

## First run

A first launch is three questions, all answered before any window is drawn: no
board file on disk, `SimpleKanbanChoseStarter` not yet set, and the process is
not the test host. When all three hold, `SimpleKanbanApp.init()` builds
`FirstRun.emptyStore()` — a store with **no tasks, no boards and no labels** —
and the root covers it with `FirstRunView`: a `fullScreenCover` on iOS, a `sheet`
on macOS, `interactiveDismissDisabled` and no Skip button.

There is no Skip because the empty board *is* the skip: **Empty Board** is one of
the five rows. The others are **Personal** (4 columns, 7 cards), **Sprint** (5,
with In Review), **Content Calendar** (5) and **Sample Board** — the seed this
app has always shipped, now offered rather than imposed.

Choosing one calls `store.importBoard(template.snapshot)`. Merging a template
into a board with nothing on it reproduces the template exactly, which is why
first run needed no new `BoardStore` API and why the choice costs exactly one
⌘Z: it is an import like any other. `SeedData.starters` is the list, and
`BoardTemplate` is a board, its columns, its labels and its cards in the shape
`importBoard` already takes.

Both hooks a harness needs are `DEBUG`-only launch arguments —
`-SimpleKanbanFirstRun YES` forces the picker, `-SimpleKanbanSkipFirstRun YES`
suppresses it. **The forced one is pointed at a throwaway file**, not
`BoardFile.default`: an empty store aimed at somebody's real board would write
over it on the next flush, which it did once before the file was redirected.

### Starting over

**Settings ▸ Delete everything…** raises the same five rows. It used to be
*Reset to the sample board*, which answered the question instead of asking it —
somebody who wanted rid of their board got the demo whether they wanted it or
not, and the only way to an empty one was to delete fifteen cards by hand.

Both sites present through `starterPicker(isPresented:occasion:palette:choose:cancel:)`,
so the cover-on-iOS/sheet-on-macOS choice and the metrics that go with it cannot
drift apart. `FirstRunView.Occasion` carries the three strings that differ, on
the enum rather than in the view so `StartingOverTests` can read them — a picker
that still says *Welcome to Simple Kanban* while it replaces somebody's board is
the failure the split exists to prevent.

Two differences from a first launch, both about there being something to lose:

- **A Cancel.** `cancel` is one optional closure that the button, the Escape key
  and `interactiveDismissDisabled` all read, so a first launch stays inescapable
  — the empty board is its skip — and starting over cannot trap anybody into
  replacing a board they changed their mind about.
- **`startOver(with:)` replaces, where first run merges.** `importBoard` folds a
  template into what is already there, which reproduces it exactly when what is
  already there is nothing. Here it would leave the cards somebody just asked to
  be rid of sitting beside the new ones.

**Nothing is thrown away until a row is picked**, and that is a correctness
property rather than a nicety. Emptying the board when the warning is accepted
and filling it in when the picker returns costs two ⌘Z to get back from, and
opens a window where undo restores the board *underneath* a modal whose only
exit is to destroy it again. One step, taken at the choice, has neither problem —
and it is what makes the Cancel mean anything. `saveNow()` and a copy into
`backups/` come first, as they do for a restore.

## Sync

The board syncs through **SwiftData with CloudKit**, one record per task,
sub-task, activity entry, board, column and label. The granularity is the point:
a single JSON document is the wrong shape for sync, because two devices editing
different cards would conflict on the whole document, and per-record storage
lets CloudKit merge them without either side losing an edit.

**What did not change.** `BoardStore` still holds value types and still undoes by
snapshot. `@Model` classes were kept at the persistence boundary rather than
made the in-memory representation, because converting the store would have taken
out undo, the spec's transition rules and most of the suite for no sync benefit —
the records are what CloudKit reconciles, and the store never sees one.

**`board.json` did not go away either**, and the two are not redundant:

| | holds | answers |
| --- | --- | --- |
| `board.store` (SwiftData) | the board as records | what another device changed |
| `board.json` | the board as a document | backups, export, import, and the corrupt-file rescue |

Both are written on every save. At launch the records are asked **first**, since
they are the ones another device can have written since this one last looked;
`board.json` answers when the records are empty — the upgrade, where the JSON
board is folded into them once — and when the store cannot be opened at all,
which is the failure the quarantine machinery exists for and must never look
like an empty board.

### A store that opened and then failed to read is not an empty one

Three things can come back from that first ask, and the third used to be
dressed as the first: the records, nothing, or an **error**. `restored` read
them through `try?`, which makes "held nothing" and "the read failed" the same
`nil` — and the file path both answers ends in a push that, with nothing to
diff against, rewrites **every** record. So a transient read failure — the
container mid-migration, a CloudKit schema push in flight, disk pressure —
handed another device's newer board a stale overwrite, silently.

Now a failed read sets `BoardStore.isSyncReadBlocked`: the file still puts a
board on screen and every save still reaches `board.json`, but **no push
leaves this device until a read succeeds**, because a push over records that
were never read is the overwrite above. Settings ▸ Sync states the condition —
it is a standing one, not an error to report once. The read is retried by
every save, every remote-change notification and every manual sync, and the
first one that succeeds runs the one merge in the app that is done by hand —
`recoverFromBlockedSync` — since the normal order (push, then read back the
union) is exactly what is forbidden here. The merge works at the one
granularity that carries a timestamp: per task, newer `updatedAt` wins, the
same last-writer-wins the schema settles duplicate records with; a task only
the records hold arrived and is adopted; one only this side holds is kept if
it was touched while blocked and otherwise let go, because a task the records
no longer hold is one another device deleted. Everything coarser — boards,
labels, views, the palette — has no timestamp to argue with, so the records
win, as they do in every other merge. A store that reads back *empty* is one
that has been reset, and is seeded from this device the way a first launch
would have. `SyncReadFailureTests` drives all of it through `SyncStoring`, the
seam that exists because a real container cannot be made to fail on command.

The same family of silent losses had two smaller members in the store itself,
both fixed and both pinned by `SyncEncodingFailureTests`: an activity entry
whose kind failed to encode was written as an **empty row** — which satisfied
the already-written skip on every later pass, was never repaired, and was
dropped by `value(of:)` on every other device — and now is not written at all
until the task next changes, with a log line for the wait; and themes that
failed to encode wrote `nil` over the synced value, which the next device read
as `.seed` — the previous value now stands instead. The complement got its
guard too: a row whose kind this build cannot *decode* — a newer build's entry
— is left out of the value, and the orphan sweep no longer deletes it for
being absent, which is the round-trip promise `StoredActivity.kind`'s comment
was already making.

### Pull to sync

The desk has a window in front of you and the touch platforms have a list in your
hand, so **iPhone and iPad ask for a sync by pulling a list of cards past its
top** — `PullToSync`, applied to the board's columns, the Inbox, a saved view and
Search. It is `refreshable`, so the gesture and the spinner are the system's own.

**It is not a fetch, because there is nothing to call.**
`NSPersistentCloudKitContainer` schedules its own trips and takes no instruction
about when one happens. What a pull can do is the half that belongs to this
device, and
`syncNow(settling:)` does both parts of it: whatever has not been pushed goes now
— the push rides the save debounce, so a card ticked a moment ago may still be
sitting here — and whatever has already come down is adopted, through the same
`mergeRemoteChanges` a change notification arrives on. Then the spinner is held a
beat, which is not decoration: the board is mirrored asynchronously, so a change
that push provokes lands shortly after, and the beat is the difference between
the other device's card appearing under the spinner and appearing a moment after
the user has decided the pull did nothing.

**Nothing is attached where there is nothing to ask.** A spinner is a promise
that something is being checked, and a device with sync switched off, no iCloud
account, or a build carrying no entitlement has no such thing to offer: the list
simply bounces. That is also why the gesture cannot be driven on a simulator,
where `SIMPLE_KANBAN_CLOUDKIT` is off by construction — see
**`iphoneos*`, not `iphone*`**.

**The bounce comes with it.** Every card surface asks for
`.scrollBounceBehavior(.basedOnSize)`, so a column whose cards do not fill it does
not rubber-band — and a list that cannot be pulled past a top it is already at
cannot be pulled to refresh either. The half-empty column is precisely where
somebody waiting on another device will pull, so the modifier sets `.always` on
the vertical axis for as long as the refresh is live, from closer to the scroll
view than the call site's own line.

**A read is not news.** `mergeRemoteChanges` now compares what the records hold
against what the board holds before adopting it, and reports whether anything
arrived. Adopting the same values over the same values is invisible, but the
stamp beside it is not: `lastSyncedAt` is the sentence Settings prints as *last
change from another device*, and a pull is the user asking at a moment of their
own choosing — so a board with nothing to say would have been saying it in the
present tense, once per pull. The comparison is against exactly what the merge
adopts and nothing else, since the trash, the themes and the active board stay
this device's own across one.

**The phone's Inbox is the one surface that gives the gesture back.** It is a
sheet dragged up from the foot of the screen and its own dismissal is a downward
drag, so a pull past the top of its cards was one thumb asking for two things a
few points apart — which of them you got depended on where it landed.
`PhoneCardStack` takes a `pullsToSync` and the sheet passes `false`. The iPad's
Inbox is a panel standing in the window with nothing to dismiss, and keeps the
pull; so do the board's columns on both.

**A finished check says so.** A pull that found nothing looks exactly like a pull
that did not happen — the spinner leaves either way — and "nothing was waiting"
is usually the answer somebody pulling is after. So `syncNow` ends by raising an
`Announcement` on the same strip the trash uses: **Up to date** when the records
held nothing new, **Board updated** when they did, with the glyph carried by the
announcement rather than assumed by the card. It is raised *after* the settle, so
it lands as the spinner leaves rather than under it, and only for a check
somebody asked for — a merge arriving on its own says what it has to say by
changing the board, and a card per push would be several an hour on a board two
people are working.

**The desk asks with a button.** A window that is already in front of you has
no pull to borrow, so `MacStatusBar` ends with **Sync Now** — after the sentence
about the last save, in the strip that already reports what the board managed to
do with itself. It runs the same `syncNow(settling:)`, and spins its glyph for
the same beat. Where the touch platforms attach no gesture, the button is greyed
rather than gone, and its tooltip says which of the two reasons applies: sync
switched off, or iCloud unavailable this launch. A build with no entitlement
draws no button at all — that state can never be fixed from here, and Settings is
where it is explained.

**Measured where it could be measured, and one surface could not be.** Whether
a pull fires a refresh is a claim about a gesture, so it was driven on a
simulator against a temporary marker inside `syncNow`: a board column on a phone
fires it, and so does one on an iPad. The flat surfaces are a `List`, whose
refresh is UIKit's own control rather than SwiftUI's, and no synthesised drag
would fire it — three gestures, from the top of the list, with and without the
content margins, on a build where the pull was forced on. That is as likely to be
XCUITest's limit as SwiftUI's: `List` with `refreshable` is the canonical
pairing, and the modifier is the same one the columns carry. It is left in place
and left unproven, which is the one claim in this section nothing here backs.

**One surface has no top to pull past.** A saved view on an iPad is
`TaskColumnsView`'s down-then-across flow, which wraps its cards into columns and
scrolls **sideways** — see **The views wrap into columns**. There is no vertical
pull to hang a refresh on there, and a horizontal scroll view will not take one.
The iPad's board columns and its Inbox pull normally; so does a saved view on a
phone, which scrolls downward in both orientations.

### What CloudKit will not do for you

Every rule in `SyncSchema.swift` is one the framework cannot enforce once the
data is on a server it does not exclusively own, and every one of them fails at
container-open time on somebody's device rather than at compile time here —
which is why `SyncStoreTests.theSchemaIsOneCloudKitCanTake` walks the schema and
asserts them:

- **No unique constraints.** Two records can share an id, so `BoardSyncStore`
  settles them on the way out: newest `updatedAt` wins, which is
  last-writer-wins applied to a whole record. Sub-tasks and activity merge by id
  *inside* the record instead, so an edit made on each of two devices keeps both.
- **Every relationship optional**, because iCloud does not process relationship
  changes atomically — which is also why a task record carrying one of
  `boardID`/`columnID` and not the other reads as **unfiled** rather than as a
  card in a column nobody can find.
- **Explicit inverses**, since changes arrive in an indeterminate order.
- **No `.deny` delete rule.** Cards own their checklists and their history, so
  those cascade.
- **The schema is additive only** once promoted to production: a model type
  cannot be removed and an attribute cannot change type. Treat `SyncSchema.swift`
  the way `BoardMigration.swift` treats the JSON shape.

One trap worth naming, because it costs an afternoon: **SwiftData reads a
`Codable` value's shape from the type.** `CalendarDay` encodes through a
*single-value* container, so the store lays out for its three `Int`s and then
trips over the string that arrives — surfacing as
`Could not cast __NSCFNumber to NSString` at *read* time. Every value type in the
schema is therefore stored as something CloudKit has natively: the due day as
`"2026-08-20"`, and `SwatchColor`/`LabelTone` as JSON `Data`.

### It is on, and what turning it on took

The capability was a **provisioning step** rather than a code one, and that step
is done: the App ID `com.n14395.SimpleKanban` is registered under team
`P52946XHRJ` with iCloud ▸ CloudKit and push, and the container
`iCloud.com.n14395.SimpleKanban` exists. `xcodebuild -allowProvisioningUpdates`
did it — the Xcode account session was already good, so no dialog appeared — and
the profiles it wrote are *Mac Team Provisioning Profile: com.n14395.SimpleKanban*
and its iOS twin, both carrying `icloud-container-identifiers` and
`aps-environment`. All three `CODE_SIGN_ENTITLEMENTS` lines in `project.yml` now
point at the `-CloudKit` files and the compilation condition beneath them is
live. **A CloudKit container cannot be deleted**, so that name is permanent on
the account; the App ID could go, the container cannot.

What is left is the CloudKit dashboard: the development schema initialises itself
on first run, and **promoting it to production is a separate, one-way step** to
take before shipping. After that the schema is additive only — see above. The
step before *that* is the one the suite cannot take: a real two-device merge,
which `Tools/sync-merge-checklist.md` scripts scenario by scenario — run it,
record the result here, then promote (the dashboard steps are at the end of the
checklist).

**To put it back**, point the macOS `CODE_SIGN_ENTITLEMENTS` line at the plain
`Resources/SimpleKanban.entitlements` and comment the condition out. Nothing else
changes: `BoardSyncStore` reads the entitlement rather than being told about it,
and a build without one runs the same records locally — the board is saved, and
Settings ▸ Sync says it is not travelling.

**`iphoneos*`, not `iphone*`, and this was measured rather than reasoned.** The
compilation condition first went in under the wider spelling, which matches the
*simulator* as well — and a simulator build is never entitled whatever the
`CODE_SIGN_ENTITLEMENTS` lines say: Xcode strips the dict to empty, which
`codesign -d --entitlements` on the built `.app` confirms. So the flag there
claimed a container the process did not hold, which is precisely the arrangement
`CloudKitEntitlement` exists to prevent. On an iPhone 17 Pro simulator the app
duly asked, and CoreData answered `CKAccountStatusNoAccount` and carried on —
**not** the trap below, and only because no iCloud account was signed in on that
device. Sign one in and the entitlement is the next thing left to fail. Narrowed
to `iphoneos*`, the simulator logs no `CoreData+CloudKit` line at all, which is
the state a UI test run wants anyway.

### Asking for a container you were not signed for is a crash

Not a failure. Not an error. A crash, and one that costs an afternoon to place,
so it is worth stating plainly:

`ModelContainer.init` accepts `cloudKitDatabase: .private(…)` on a build with no
iCloud entitlement, **succeeds**, and hands back a working store. CoreData's
mirroring delegate then reaches `CKContainer` on `com.apple.coredata.cloudkit.queue`
and traps — `EXC_BREAKPOINT` inside
`-[PFCloudKitContainerProvider containerWithIdentifier:options:]`, on a thread this
app does not own, with nothing on the stack it could have caught. The obvious
guard is a `do`/`catch` around the open, and it does exactly nothing.

So the entitlement is checked **before** the ask, by `CloudKitEntitlement`, and
`BoardSyncStore.app(syncing:at:)` is the only place in the app allowed to name a
container. The decision itself is a pure function —
`BoardSyncStore.cloudContainer(syncing:isRunningTests:signedContainers:)` — because
a crash cannot be caught by a test after the fact, so the thing that has to be
right is the thing that runs before it. `SyncEntitlementTests` puts it through
every combination, and pins the end of the rope too: whatever the preference
says, the container the app opens must report `cloudKitContainerIdentifier == nil`.

The two platforms answer the entitlement question differently, and neither answer
is a preference:

- **macOS reads its own code signature** through `SecTask`, so it cannot drift
  from what the app was built with. `SyncEntitlementTests.theSignatureAgreesWithItself`
  cross-checks that reading against `SecCode`, which reads the signature off the
  bundle on disk — two frameworks, one fact.
- **iOS has no public API for it** (`SecTask` is macOS-only in the SDK, and the
  private spelling is not worth a rejection), so it reads the
  `SIMPLE_KANBAN_CLOUDKIT` compilation condition, set beside the entitlements file
  it has to agree with in `project.yml`.

The suite is a third `nil`: it runs as the app's own test host under the app's own
bundle identifier, so an entitled build would otherwise hand the fixtures to
whatever iCloud account the machine is signed in to — and then to every device on
it. Same rule as `BoardFile.default`, with more at stake.

## Packaging, the icon and the update check

**The icon** is drawn rather than drawn *in*: `swift Tools/make-app-icon.swift`
writes all eleven PNGs and the appiconset's `Contents.json` together, so a slot
without an image — which `actool` accepts silently — cannot happen by editing one
and not the other (`PackagingTests.everyAppIconSlotHasItsImage` holds the pairing
from the other end).

**The mark is a transcription, not an invention.** `Tools/simple-kanban-icon-4f.svg`
is the design and sits beside the generator so the two can be read together:
three columns of white cards under their header rules — stacks of **2, 3 and 1**,
because a board is not a staircase — on a peach-to-violet diagonal, `#FFB48A`
through `#E0559B` to `#7B2CD9`. Every number in `bars` is the SVG's own, in the
SVG's own 100-unit box. A program rather than a rasteriser because a rasteriser
is a dependency and the drawing is nine rounded rectangles and a gradient.

macOS art is inset on Apple's 824-of-1024 grid and superelliptical, and casts the
shadow the Dock expects; iOS is full-bleed and alpha-free, which the App Store
requires and which is also why the SVG's own squircle clip is *not* applied there
— the system masks it, and a pre-rounded square arrives with dark corners. At
32pt and below the cards are sub-pixel and the gaps between them close up, so the
mark simplifies to the three stacks as single capsules: the same silhouette with
the detail taken out, which is what Apple's own icons do with hand-drawn small
artwork.

**Everything is named sRGB — the colours, the bitmap and the gradient.**
`CGColor(red:green:blue:alpha:)` makes a colour in the *generic* RGB space, and
drawing one into a `DeviceRGB` bitmap converts it. Measured on the first render:
every stop came out visibly lighter than the design — `#FFB48A` arrived as
`#FEC09B`, `#E0559B` as `#E970AC`, and `#7B2CD9`, the one that carries the icon,
as `#904BE0`. A hex in the design has to be the hex in the file, so nothing is
left to convert.

**What the bundle declares**, all from `project.yml` rather than written twice:
`CFBundleShortVersionString` and `CFBundleVersion` come from
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`; `CFBundleIconName` (an iOS
submission is rejected without it, and the About panel's `UIImage(named:)` only
resolves an icon that has one); `NSHumanReadableCopyright`, which the macOS About
panel reads; and `UILaunchScreen: { UIColorName: LaunchBackground }`, so the
first frame is the board's own background rather than a white flash.
`PrivacyInfo.xcprivacy` is a bundled resource declaring no tracking, no collected
data, and a reason for each required-reason API the app touches — `UserDefaults`
(`CA92.1`) and file timestamps (`C617.1`, which `BoardFile.recentBackups` reads).

**The update check is a `GET` and nothing else.** `UpdateChecker` reads
`/repos/{SKUpdateRepository}/releases/latest` from api.github.com, compares the
tag numerically (so 1.10 is newer than 1.9, and a tag it cannot parse is never
newer), and offers a link. It has no timer, no launch check and no auto-update:
the only thing that starts it is the About panel's **Check for Updates…**, and
the panel says what pressing it does before it is pressed
(`UpdateChecker.disclosure`). That is the whole reason it is not Sparkle — a
framework, a signing key, an appcast to host and an auto-updater to be trusted,
for one unauthenticated request for public JSON. The sandbox entitlement it needs
is `com.apple.security.network.client`; without it the request fails in a way
nothing on screen can explain.

`SKUpdateRepository` and `SKReleasesPage` live in the plist so a fork changes one
line — and **`./build.sh --publish` refuses to cut a release when the built app's
`SKUpdateRepository` and the `origin` remote disagree**, because a release
published from a repository the installed copies do not poll is a silent,
permanent failure.

## Tests

`SimpleKanbanTests` is a Swift Testing target — `import Testing`, `@Test`,
`#expect`, `#require`, no XCTest — and it builds for both destinations off the
same scheme:

```sh
xcodebuild test -project SimpleKanban.xcodeproj -scheme SimpleKanban -destination 'platform=macOS'
xcodebuild test -project SimpleKanban.xcodeproj -scheme SimpleKanban \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Pick a simulator that exists — `xcrun simctl list devices available`. Half the
view code is behind `#if os(macOS)` / `#if os(iOS)`, so a green macOS run says
nothing about iOS. macOS runs a few dozen tests more than iOS, from the files
inside `#if os(macOS)`: `UndoHandoverTests` needs a real window, and
`BoardKeyboardTests`, `MenuDeclarationTests` and `FocusRingTests` describe a
pointer-and-keyboard surface the phone does not have.

Two of those are now behind a guard they have outgrown. `BoardFocusMap`,
`BoardKeyboard` and `BoardTaskCard.Ring` moved to `Sources/Shared` with the board
in 5.1, so `BoardKeyboardTests` and `FocusRingTests` would compile and pass on
iOS — an iPad with a hardware keyboard runs exactly that code. The `#if
os(macOS)` at the top of the file was left where it was rather than changed in
the same pass; dropping it is a one-line edit and about forty more tests on iOS.

| suite | covers |
| --- | --- |
| `CalendarDayTests` | day arithmetic, month/leap/DST boundaries, `Codable` round-trip, stability across time zones |
| `PriorityTests` | the enum three other things lean on: `allCases` running most urgent first, which *is* the priority sort and the order the Set Priority submenu draws, with `leastFirst` its exact reverse for the editor's picker; `Comparable` the right way round, which is what lets a filter say `>= .high`; the default being the floor and the same constant the mint uses; every spelling a shipped board file carries — the v6 tokens and the pre-v6 display strings, with `Max` deliberately not among the latter — and an unknown token *throwing* rather than falling back, which is the whole reason the fourth priority cost a format version |
| `DueDateTests` | every label and urgency boundary, against an injected `today` |
| `BoardStoreMutationTests` | move and its Done tick, add, delete and where the selection falls, complete/reopen, the tick itself — `toggleCompletion` going both ways, a completed card still tickable though `canComplete` says no, a board with no Done column to reach drawing a dead one, and an archived card offering none — discarding a capture nothing was filled into — emptied again, pickers that came home, whitespace, a default due date, and the seven fills that keep it, including the board menu's — the sub-task reorder offset, the column a launch opens on and the phone's column step and its wrap, label toggle, priority, due, `updatedAt` and the header counts |
| `EditingSessionTests` | one entry per session; none when nothing changed; a blank title or sub-task restored; first naming is not a rename; independence per surface, per task and per sub-task row — driven through the selection and sheet changes that end a session, which is where the scoping actually lives |
| `DraftTests` | sub-task and label drafts are per (surface, task), and go when the task does |
| `UndoTests` | every mutation undoes and redoes; a deleted task returns to its own index; a text session is one step while each picker change inside one is its own; keystrokes typed before an interleaved step are still reachable, and a ⌘Z aimed at an older step keeps what is still being typed; the Done tick's sub-task flags come back exactly; a blank title restored before the step opens on the bulk delete as well as the singular one, which is the only place that ordering can go wrong |
| `UndoHandoverTests` | macOS only — a real `RootView` in a real `NSWindow` hands that window's `UndoManager` to the store. Break the handover and every other undo test still passes while ⌘Z in the shipping app does nothing |
| `PersistenceTests` | v5 round-trip of every field, `archivedAt` included; the v1 fixtures migrating, including a file with no `version` key at all; corrupt, truncated, wrong-shape and future-version files falling back *and* being quarantined; `nextSerial` continuity; rolling backups; an overtaken write dropped rather than undoing a newer one; the debounce coalescing a burst, and `saveNow()` bypassing it |
| `SearchTests` | multi-token AND, diacritic folding, the column grouping *ignoring* the query, an archived task falling out of every result, and memo invalidation — across two edits in one instant, a delete, and an undo and its redo |
| `TaskSearchTests` | the ranking, one rung at a time: a title that *is* the query above one that starts with it, a word of the title above a letter run inside a word, a hyphen starting a word, the title above the note, the sum over tokens, folding on both sides, and a missing token being a miss however well the rest scored. Then what the store does with it — a title hit ahead of a note hit whatever order the board holds them in, `updatedAt` breaking a tie, an empty query being every task rather than none, and the results spanning the Inbox as well as every board |
| `SearchScopingTests` | which surfaces the one query is allowed to act on — the whole truth table of tab × saved view for `mobileAppliesQuery`, the "Filtered" notice, the add row and the column chips; a query typed on Search leaving the Board alone, and the Inbox's slide-over out of its reach whatever tab is under it; whitespace not counting as a filter; clearing costing no undo step and no write; picking a tab or capturing a card leaving the saved view; `allowsCardDrag` off in every saved view and *on* under a query; and the rule the results panel is for — no column slice, Inbox or saved view narrowed by a query, while the search itself still answers from every board at once |
| `LabelTests` | slug trimming, empty-slug fallback, the 40-character cap, rename keeping the key, delete stripping it from every task |
| `ThemeTests` | the theme engine, and almost none of it is checkable by looking: the twenty presets in the document's own order with Ember eleventh, Ember's every value against the page it was transcribed from, the two the document sets in italic and the one with four gradient stops, every preset's faces being bundled and resolving at all five weights; the colour codec — hex out, hex/rgba/shorthand in, nonsense refused, opacity quantised so a theme survives its own export; the CSS gradient angle, pinned on the four axes where it is exact and on a corner where it is not; the two slots, a theme going only into the one its kind names, a slot naming nothing falling back, a preset refusing to be saved over; what a theme paints — the accent, max priority being the overdue hue, the due chips, a label's chip through the rule rather than off the stored pair, and the contrast floor holding whatever the theme's ink tiers say; and the file — every preset round-tripping, the two hand-written shapes accepted, and a broken colour naming the field it is in |
| `TransferTests` | the drag payloads — the plain-text and `Codable` forms of a card, a checklist row and a column, that a column's carries the board it is on, and that all three exported type identifiers match the ones `project.yml` declares |
| `SavedViewTests` | every view's badge equalling its list's length whenever nothing is typed, and a query being the only thing that may part them; every predicate at the day either side of every bound it draws — Today carrying overdue, Upcoming strictly ahead, `0...6` for the week — the cap at twenty, the two views that override the board's order and the four that do not, Done left out of four of six, archived tasks in one of six, and a query narrowing a view *after* its cap rather than before |
| `SavedViewSeedTests` | **the acceptance test for custom views**: each of the seeded seven, rebuilt out of criteria, gathering exactly what the enum's hand-written predicate gathered — the predicates transcribed into the suite, since the thing they are the reference for deleted them, and run card by card over every `WeekMeaning` (the week decides one of the seven and is a preference, so the default alone tests a third of *Due this week*), then again over a board with cards filed away, which is the half a live board cannot ask. Then the two claims that are not a predicate: *Recently updated* still newest-first and capped at twenty against a 25-card fixture written oldest-first, and the Archive still newest-filing against three cards written in the reverse of the order they must come back in. Then that the other five leave the board's own order alone; that no seeded rule needs more than three criteria to say; and that every criterion in every seeded rule is a field-and-comparator pair the editor's own pickers can actually produce |
| `ColumnTests` | columns as data — add, rename, recolour, reorder and delete, each of them one ⌘Z and one write; a column keeping the abbreviation and the dot it was *made* with, and borrowing its name for the first and `BoardColumn.defaultDot` for the second when the composer's fields are left alone; a delete relocating its cards and logging it, and being refused rather than ignored when it would leave no Done column or no other one; columns surviving a relaunch, and no columns surviving one too, because no boards is a state rather than damage; and the v3 → v4 step mapping every legacy column id, on the task and inside the activity feed |
| `DoneColumnTests` | the board's **last** column rather than the *word* carrying every Done behaviour — against a board that also holds a middle column called "Done" — after it has been renamed, recoloured and had the columns around it shuffled, and across a relaunch; that it cannot be dragged off the end, dropped away, or displaced by a new column; that a board built by hand gains it with its first column and a single-column board has none; and that each board's Done is its own while another board has one |
| `BoardTests` | boards created, renamed, recoloured, reordered and deleted; switching boards changing the columns, the title and every count; the Inbox being the same list whichever board is active and a quick capture never picking one; codes minted from the destination and never changing; a board deleted sending its cards to the Inbox, its neighbour taking over, and the last one going without taking the Inbox with it — after which the empty board list is what a relaunch reads back, and a fresh board can still be made from it; the active board surviving a relaunch while the surface does not; and a v4 file splitting between the default board and the Inbox |
| `PlacementInvariantTests` | the one rule the model exists to keep — a task is unfiled or on a board in one of its columns, never half of either — checked after every store method that can touch a placement, four ways over: alone, in one long sequence, undone one at a time, and undone in a full drain. Plus the illegal pairs refused rather than stored at all three doors that take a placement from outside — `file` leaving the card where it was, `move` the same, `addTask` landing it in the Inbox and minting an `IN-` code for it; a card whose board and column disagree placed by its column; a file carrying two cards under one id loading with the second dropped; `reopen` reading a card's history against its *own* board, so an id it recognises from elsewhere cannot carry the card to a board nobody was looking at; the bulk move refusing the same pair, which is the fourth door and the only one that does not go through the singular `move`; and a code surviving every journey a card can take |
| `ArchiveTests` | a filed task leaving `searchResults`, every column slice, every board count and every view but the Archive while staying in the file; the surfaces moving off it; `archiveCompleted` as one ⌘Z on one instant, skipping what is already filed; restore putting it back in its own column; filing moving no `updatedAt` while still invalidating the grouping and the search; `complete` and `reopen` refusing an archived task outright, at no undo cost; the rolling seven-day meter, at both ends of its window, against a stamp in the future, and reading `updatedAt` rather than `createdAt`. Plus what the Task menu may do to a selection of filed cards, which the Archive surface's own ⌘A makes one keystroke away: every item on it disabled, nothing for any of them to act on, no step filed and no stamp moved — and the four commands that *do* still apply to a filed card, because reading one, copying its code or throwing it away are things a person does in an archive |
| `MigrationTests` | the chain — `board-v2.json` arriving as v5 field for field with nothing archived, both v1 fixtures walking the whole way, a v1 board and a v2 board taking the same last step, a v5 file read back without being migrated again, an unarchived board writing no `archivedAt` key at all, and a version-6 file refused and quarantined intact |
| `MigrationChainTests` | the same chain asked of **every** fixture in the bundle at once, enumerated off disk rather than listed: each reaching the current version, each splitting its cards between the default board and the Inbox, the v3 and v4 fixtures splitting their six cards identically, each link leaving its own mark on a v1 board, the same bytes reaching the same board twice over, no fixture needing repair on the way into the store, the active board written into the file itself, and a file one version newer than *this build* refused and put somewhere safe |
| `DayRolloverTests` | the day clock built from an instant either side of midnight, and the Today count and each saved view's membership before and after — including the three views that must *not* move, a year end, and the weekly meter's window rolling with it; plus the wake itself — a second either side of the boundary, and the DST days where the next midnight is 23 or 25 hours off rather than 24 |
| `CommandTests` | the selection as a set — `selectedID` reading as one task or none, a second card ending the session the inspector left on the first, a range following the order the surface draws in, ⌘A following the surface and the query — and the bulk commands: one named step apiece, board order preserved, a mixed selection labelled *on* before it comes off, part of a selection deleted leaving the rest, and a bulk command with nothing to do staying off the Edit menu. Plus the shortcut vocabulary: no two commands claiming one press, ⌘N/⇧⌘N saying what the menu says, the system's own commands listed but not declared, and the board's keys getting no menu item to shadow a text field with |
| `TrashTests` | throwing away, getting back and getting rid of, asked once per kind because the three are not one kind with three names. A task off the board and into the trash and back into the placement it had, with `restoredFromTrash` on its history; a column trashed while its cards move to the first column left, and restored to the index it sat at; a board trashed while its cards go to the Inbox, its columns travelling inside it, and restored to its place in the sidebar. Then the edges: a card whose column has gone comes back to the Inbox rather than being refused, a *column* whose board has gone is refused and says why and is still there to try again after the board, and a refusal registers no ⌘Z. Undo across all three verbs — a trash undone takes the row back out of the trash too, which is the whole reason `trash` is in `BoardMutation` — plus the thirty days: counted off the calendar rather than in seconds so a clock change cannot move them, reading 30 on the day rather than the 29 elapsed time floors to, filtered out of the list before they are swept out of the file, and swept on the way into `restored`. Then the file: three kinds round-tripping, and a v6 file with no `trash` key at all reading as an empty one rather than as a corrupt board. Then the card that says so: naming what went for each of the three kinds, counting a selection rather than announcing four times, saying nothing at all about a refusal, two announcements with one wording still being two, and a ⌘Z taking the sentence away with the act |
| `SelectionTests` | the selection as a set, asked where it can break: a ⇧-click range including both of its ends in either direction, a run of them sweeping from the one anchor, ⌘A leaving the archive out and the anchor on the first row, and clearing taking the anchor with it. Then the bulk commands *counted* rather than inspected — every one of the eight filing exactly one registration whatever the size of the selection, a three-card delete undoing to indices 1, 3 and 5 rather than to the end of the array, and an empty, a stale or an already-satisfied selection registering nothing. Then the session-ending the set had to keep: the card the inspector was on losing its session even when it stays selected while others are added around it, the sheet's session on the same card surviving, and the ended session filing the typing as a ⌘Z of its own. Plus a bulk move of four cards arriving in the order the board had them, every position pinned — two cards is a coin toss, because `Set` hashing is seeded per process; a selection the command applies to only *half* of, where the step is named for what changed rather than for what was aimed at and the rest come out untouched; the menu item titled from that same count; the anchor moving when its card is ⌘-clicked out of the selection; ⌘N putting its surface up before opening the composer, and the bar's `+` landing in the Inbox with the panel out and a board on screen it declined to use; ⌘F bumping a counter rather than setting a flag; and the rule that keeps the two rings on one card — focus arriving takes the selection with it, unless a ⌘ or ⇧ is held for the click that has not landed yet, or the card it landed on was already part of a multi-selection |
| `ShortcutTests` | `AppCommand` as the one vocabulary. No two commands claiming the press *the system will dispatch* — matched on the resolved `KeyEquivalent` and modifier mask, folded to lower case, rather than on the enum's spelling of them; every command titled, uniquely, in title case; the commands with no key named so that adding one is a decision; an unbuilt command holding no key hostage (vacuous now that nothing is unbuilt, and kept for the next one); ⌘N/⇧⌘N and nothing else answering to them; and no shortcut printing a private-use glyph, which is what `AppKey` exists for — `KeyEquivalent.leftArrow` renders as nothing at all. Then the anti-drift claim itself: the sheet's rows and the menu bar's are both generated from `AppCommand.commands(in:)`, every menu row appears in the sheet saying the same thing, and the difference between the two is exactly the board's own keys plus the system's Undo and Redo. `MenuDeclarationTests` then reads `BoardCommands.swift` itself, because a `Commands` body has nothing to enumerate at runtime and a suite that models the menu cannot notice a block commented out of it: every menu item declared into exactly one `AppMenuSection`, each block belonging to one menu and covering that menu's items in order, and the body drawing every block once under the anchor it belongs to |
| `BoardKeyboardTests` | macOS only — how the arrows move around the board, as a value rather than a view: clamping at the ends, keeping the row sideways, stepping over an empty column while ⌥ lands in it, reading only what is *visible*, and where focus falls after a delete. Plus the key matcher — ⌥ as the whole difference between moving focus and moving the card, Space and ⌘⏎ both reaching completion, a press carrying caps lock still matching, and no two of the board's keys claiming one press. Then what each key *does*, through `BoardKeyboard.perform`: the arrows moving focus and the inspector following it, a refusal at each of the four edges keeping the key and the card it was on, ⌥→ walking a card across the board with focus on it, a card refusing to leave either end, ⏎ opening the detail surface, Space toggling one card both ways and never reopening a selection, ⌘⌫ handing focus to the neighbour and then to nothing, ⌘A and ⎋ — and that nothing the card claims falls through to the dispatcher's `default`. `FocusRingTests` holds the two rings apart — a card can wear both, so they differ in width *and* inset rather than only in colour — and pins when the inner one is drawn at all: not on the card that is the whole selection, and back again inside a multi-selection or on a focused card ⌘-clicked out of one |
| `KeyOwnershipTests` | macOS only — one owner per press across the two surfaces that both handle keys. ⌘⌫ and ⌘⏎ reaching no card on either surface while the vocabulary still names them; Space and a bare ⏎ still reaching one; `menuOwnedShortcuts` written out as the eight presses the menu bar puts a key equivalent on and checked against the seven the board keeps; the rule stated over the whole vocabulary rather than over the two keys that collide today; and the converse, so a widened exclusion cannot mute a card — every command a card carries still has a press that reaches it. The split was a single defaulted argument at one call site, and the suite was blind to losing it in either direction |
| `PaletteSemanticTests` | the semantic colours, asked what a view cannot ask itself: every accent in either scheme keeping its label above 4.5:1 against the accent it is drawn on, and the one accent that follows the colour scheme taking its label with it. `.white` on the dark-mode ink accent scores 1.2:1, which is text that is simply not there |
| `SaveContractTests` | every public board mutation reaching the disk, one store and one file apiece |
| `UndoHarnessTests` | every public board mutation registering exactly one named step that undoes cleanly, and the list of the ones that deliberately register nothing — plus how many there are, which is the only thing stopping a new mutation being quietly left out |
| `ColumnReorderTests` | dropping a column into the gap a caret names, at the seam the settings sheet's drop closure calls — the board's strip no longer offers the drag at all. Both directions, because `move(fromOffsets:toOffset:)` counts in the pre-move array and the off-by-one only shows travelling down — a rule with it backwards still looks right in half the drags anybody tries. Then the head of the list, which the old drop-on-a-row rule could not name; the gap above Done as the end of the board and nothing landing after it; the refusals — against itself, into the two gaps it already sits between, from another board, and naming a column the board no longer has; that the whole order comes back on one ⌘Z; and that `BoardColumnView`'s own source carries no `ColumnTransfer` and nothing `draggable`, which is the only form the removal can be asserted in — a drag that moves nothing looks exactly like a drag the scroller stole |
| `CardDropTests` | what a drop is allowed to do, at the seam the two board drop closures call into. A card dropped on a sibling reorders and *nothing else* — same column, same count, same sub-tasks, no move written into its history — because the failure it exists for was a reorder that moved the card to Done, ticked it, moved the week's completed count and closed its outstanding sub-tasks on the way. The contrasting drop, onto a card in Done, still does all of that, so the first cannot pass by the Done behaviour having been deleted. Then a drop on the column a card is already in staying a no-op, and the two spellings of a walk up and down a column — the second said backwards, because `move` refuses a `before: nil` into the place a card already is — plus the checklist's menu going through `dropOffset` |
| `MenuKeyOwnershipByPlatformTests` | the other half of `KeyOwnershipTests`, and in a file that is not `#if os(macOS)` so it can say it: the menu bar takes keys off a card only on the platform that has one. On macOS ⌘⌫ and ⌘⏎ reach no card; on iOS `menuOwnedShortcuts` is empty and both reach the card, because `BoardCommands` is built into the macOS scene alone and nothing on iPad was taking them first. Space, a bare ⏎ and ⌥← are unchanged on both |
| `RootSurfaceTests` | iOS only — which of the two layouts a window gets. An iPad at regular width takes the desk's; a phone takes the phone's at *every* width it can reach, which is the blocker: a Max-class iPhone in landscape is a regular horizontal size class and drew the iPad's split view; an iPad in Slide Over takes the phone's; and an unresolved size class is not a licence to draw three panes |
| `CardCornerTests` | which corner of a card the tick is drawn in, and the one rule both cards ask for whether to draw it at all: an archived card wearing none — ticking a filed card used to move it between columns under a list ordered by `archivedAt`, where nothing moved to say so — and otherwise the preference deciding. Then the corner itself, read out of the source because a corner is not a value any store can be asked, including that it is *not* back in the leading one, in front of the chips and the title it used to push aside |
| `ManageSectionTests` | that all three platforms draw the same last section: the heading being **Manage** rather than the name of a row inside it, the same three rows — Labels, Trash, Settings — in the same order on the shared sidebar and on the phone's drawer, the desk having a settings row at all (a `SettingsLink`, since ⌘, is a key and not a place), and every row named for what it *is* rather than for the verb. A drift test: the section had gone three different ways at once |
| `PadListMetricTests` | where the iPad's saved-view sizes come from rather than what they are: `TaskColumnMetrics.pad` and `.desk` taking their column width and card gap from `BoardColumnView.Metrics` and their gutter from `BoardScrollView`, so a preset that copied the numbers could not drift from the board it is meant to match; plus room under the last card, but not the phone's tab-bar's worth |
| `ColumnFlowTests` | where a column of a saved view stops and the next one starts, at the seam `ColumnFlowLayout` measures into — a pure function of card heights, because a `Layout`'s `Subviews` cannot be built by a test. A column taking exactly what fits and the rest starting the next; the gaps counted being the *n − 1* between the cards rather than one per card, which is the off-by-one that wraps a column early; a card taller than the window drawn rather than dropped, and not stranding the one after it; an unbounded height reading as one column rather than as a column per card; nothing in being no columns rather than one empty one. Then the two properties: over six window heights every card is placed exactly once and in order — a saved view is sorted, so a packing that balanced its columns would be reordering it — and the column count never rises as the window grows |
| `PhoneColumnMetricTests` | the phone's half, which wraps the other way and so has no packing of its own: that the grid is handed the landscape board's own 250pt page, and what that buys once the sensor housing and the surface's own margins are taken off — two columns on a 17 Pro, three on a Pro Max, one upright |
| `MonthGridTests` | the hand-drawn calendar's arithmetic: six whole weeks for every month of a year and for both kinds of February, every row starting on the calendar's own first weekday, the month present once and in order, the edges consecutive with it and drawn from the neighbouring months, a month starting on the first column having no spill above it, the year rolling at both ends, the column headings rotated to the locale's first weekday, and the month stepping — from the 31st, across both year boundaries, and twelve steps out and back. Against a fixed Gregorian calendar and `en_GB`, so the suite does not report a different month in another region |
| `TouchTargetTests` | every touch `Metrics` preset claims 44pt — the iPad's `.pad` board presets included, since the iPad draws the desk's board at touch sizes — and no pointer preset inflates the desk; the detail panel's three header controls — the tick, the trash, the ✕ — claiming one square on both idioms, which is the only place that agreement can be stated because the tick brings its own button, plus the drawn box fitting inside it and the desk's square holding the size it was raised to; the calendar's day cell and month arrows under a finger, and its desk pair staying well under the floor; the checklist box's overhang; the chip name's ceiling; the swatch rows fitting a 375pt phone, `Board.dotPalette` staying the size and shape that row is drawn against, and every swatch on offer — board dot and label tone alike — carrying a name rather than a position. See **Touch targets** for what this suite can and cannot see |
| `ExportImportTests` | the export document — every field through an encode and a decode, the bytes matching what `BoardFile` writes so an export and a `board.json` are one format, and the exporter being handed the whole board rather than the visible one. Then the **merge**, which is where an import destroys work: both sets of tasks kept, an id collision keeping *both* cards under two ids, a code collision re-minted on the arriving card, the serial climbing above both files so the next code is free, the label vocabulary growing without being rewritten, the arriving board landing beside the one already here, a column id already in use re-minted, a board already here keeping its name and gaining only the columns it is missing, the placement invariant holding after a stranger's file is folded in, the same file twice costing nothing and no ⌘Z — collision included — and neither the accent nor the active board being the file's to change. Plus a corrupt, newer or older file each answered properly, the Markdown export's shape, and the board type matching what `project.yml` declares |
| `BackupRestoreTests` | `BoardFile.restore(from:)` and the caller it waited for — an older backup migrated on the way in, a damaged or newer one failing loudly rather than restoring an empty board, a restore replacing the live board as one ⌘Z that comes off cleanly, the board as it stood copied aside before it goes, a restore that could not read its backup costing nothing at all, and the race Phase A's per-URL write ordering exists for: a debounced write armed *before* a restore — from this store, and from a second store over the same path, where nothing can reach in and cancel it — dropped rather than landing on top of the restored board |
| `NotificationTests` | due-date reminders against a fake `TaskNotificationCenter` and a throwaway defaults suite, never the machine's own — one request per due date and no more, a change rescheduling under the same identifier rather than adding a second, completing, reopening, archiving, deleting and undoing a delete each cancelling or restoring, no due date scheduling nothing however much the card is edited, a day already gone scheduling nothing, and the 64 nearest kept when the board wants more than the system will hold. Then the identifier: the task's id through every rename, move, archive and delete, and never anything that changes. Then permission: asked on the first due date *set* rather than at launch, never twice, never after a refusal, nothing published while it is refused or the switch is off, and everything the board wanted published the moment it arrives |
| `DeepLinkTests` | `simplekanban://task/<uuid>` — round-tripping the id, matched without regard to case, and six URLs that are not ours naming nothing; a link selecting its task and opening the surface it lives on, switching boards, opening the Archive, and clearing a query that would hide it; a link to a task that has gone and a malformed one each saying so, in different words, rather than failing silently; a link arriving before the scene, consumed by the resolve that reads it, and the same link twice counting twice. Then the *other* thing `onOpenURL` is handed: a `.simplekanban` file opened from the Finder or from Files, merged as one undoable "Import Board" and reported on its own channel, and a file that is not a board saying so and leaving the board alone rather than being rejected as a broken link. Plus the scheme and the activity type declared in the bundle, without which nothing is ever handed to `onOpenURL` and every other probe here still passes |
| `PreferenceTests` | the line between the board and the person looking at it — the exact key set the board document is allowed to carry, at the top level and on a task and a board; every preference the settings surface offers set at once and the file not moving a byte, read back after a relaunch; the accent being the one setting on that screen that *is* board data, so the probe cannot pass by the store having stopped saving; session state changing nothing while the active board does; an in-memory store leaving no preference behind on the machine it ran on; and an imported file unable to reach across and change this machine's |
| `IntentTests` | `AddTaskIntent` and `ShowTodayIntent` through `TaskIntentBridge` — no destination landing in the Inbox under an `IN-` code, a named column and a named board each landing where they say and minting from that board's prefix, a due date reaching the card, a column no board has refused rather than guessed at, and the entity queries offering what the board actually has, each column named with its board. All of it on the one store the app is holding, because a second store would be a board of its own written over the real one |
| `SystemWiringTests` | the handovers every other Phase F suite passes without: the scheduler reconciled from the board, `.systemEntryPoints()` attached to a view, a store adopted into the intent bridge — **from the app's `init()`**, not a view's `.onAppear`, because an intent can perform before any scene exists — both detail surfaces publishing their task for Handoff, the settings surface reachable, and exactly one store over the real file. Read out of the source the way `MenuDeclarationTests` reads the menu: a scene has nothing to enumerate at runtime, and a modifier commented out of a `body` is invisible to everything else. This is `UndoHandoverTests`' question asked of the other joins. The three that were open at the end of Phase F were wrapped in `withKnownIssue` rather than deleted or left red — Swift Testing fails a block that *stops* failing, so wiring one up told the next agent to take the wrapper off in the same run, which is what happened |
| `WidgetDigestTests` | the whole of the contract between the app and its widget extension, because the extension evaluates nothing and there is no second place a mistake could be corrected: the Inbox carrying what is *waiting* — a ticked-off capture and a filed-away one both out, which is also what makes the list exactly the seeded Inbox view's membership; every board's columns crossing under their own short names; a column's rows being the ones the board draws, in the board's own order, with the *count* the whole column and the rows the first eight; every view's rows and its pill, where the pill is the view's own limit and not the digest's cap — *Recently updated* says twenty and carries eight; Done being the board's answer rather than a field on the card; the theme and the light/dark override travelling so a widget wears what was chosen; the day the lists were built against travelling with them, so a due chip in a widget says what the same chip says on the board; Today recognisable from the extension, which has no `SavedView` enum; and the file — a round trip, the same board twice encoding to the same bytes (which is what stops every keystroke waking every widget), and a digest from another version refused rather than migrated |
| `AppLinkTests` | the six URLs the widgets are wired with, written by one target and read by another: every destination round-tripping, no two sharing a URL, the scheme and host matched without regard to case, and seven strangers naming nothing — including a host with something after it, so a shape a later version might mean cannot be silently swallowed |
| `WidgetLinkRoutingTests` | what happens when one arrives: a board link switching boards, a column link landing on the board that column is on *now*, a view link opening it, an Inbox link putting the board back *and* the panel out, and the `+` making a capture in the Inbox with its title field asked for. Then the four deletable things each getting their own sentence when they have gone — "that view no longer exists" tells somebody which widget to fix — and the two that cannot go away never failing |
| `WidgetShareTests` | that the two bundles can actually reach each other, which every probe above would pass without: the five entitlement files read off disk, each naming the App Group its platform's code calls `containerURL(for:)` with — team-prefixed on macOS, not on iOS. There is no runtime value that could state this: the extension is another process and the app's own entitlements say nothing about it. Plus the four widget kinds being distinct, since the system stores them against every widget somebody has placed and renaming one orphans it silently |
| `DragReorderTests` | the card-to-card drop as a property rather than as an example, which is what the iPad needs: for **every** ordered pair of cards sharing a place — each column of each board, and the Inbox — the drop `BoardTaskCard` and `PhoneTaskCard` make must leave the card in that place, not change its completion, and not touch its sub-tasks, with the place holding the same set of cards afterwards. Then that it genuinely reorders — the card lands immediately ahead of the one it was dropped on, in every pair — so the first claim cannot be satisfied by a `move` that does nothing. Then the contrast, over every pair of *different* places, including a card into Done still being ticked; the column's own drop closure resolving to that column for every card on the board and staying a no-op on the column a card is already in; a drag refused under a query, under a sort and inside a saved view; and an archived card unreachable by either closure |
| `DropCaretTests` | where a dragged card says it will land, and whether it is telling the truth. A caret names a *gap*: the head of another list — the one thing the old direction-of-travel rule could not express at all — the foot of one, the two names for one gap meaning one place, and a card coming from below landing where it was pointed rather than on the other side. A drop into the gap the card is already in moving nothing *and registering no step*. A list's own ground landing the card at the foot — in a column and in the Inbox, and from the top row of the list it left as readily as from the bottom, because "always the foot" is only a rule if the row the card came from cannot change the answer — with no caret at all over an empty one, which still takes the card; the pointer inside a card beating the ground, because a named gap is not a default; `move(_:to:)` landing a card in the same place a drag does, since a ground drop is now that call; the column a card is already in offering none, because that drop moves nothing and registers no step; and none at all with nothing in the air or with a query narrowing the board. Then the caret drawn without a drag session to name the card, which is the iPad's case. Then the half that is a claim about pixels: the card rendered and the accent-coloured row found in it — looked for rather than diffed against a plain card, because in a full parallel run the same card came out 83pt where it is 110pt alone and a third of it differed for reasons that had nothing to do with a caret — against a raster whose row order is itself measured rather than assumed |
| `DragLiftTests` | when a card stops looking as though it is being carried, which the reported flash was a hundred milliseconds late for. `BoardStore.endDrag()` taking the lift off the card *and* the highlight off both places one can be — the column and the Inbox panel — and a move, including the drop that lands where the card already is, going through it. Then the half no unit test can drive, read off the source the way `DragReorderTests` reads the drop closures: nothing in the session handler ends a lift by hand, a drop carrying a card falls through the `ended` arm untouched, and the arm that ends the lift is `dataTransferCompleted` |
| `BoardRevealTests` | how far the board moves when focus arrives, and who decides. Every surface that scrolls a card into view — the strip, the column, the Inbox panel — read off the source: none of them hangs a `scrollTo` off `focus`, which is what made a click scroll the board; each answers **both** manners, centring what a key revealed and giving a click's reveal no anchor at all, so the rule cannot be met by dropping the scroll and stranding the arrow keys nor by answering a click with the centring that was the complaint; and the two routes that raise one are the keyboard, only ever centred, and the card's click, only ever into view. The scroll counts per file are asserted too, so a new one cannot be added without this being read. The detail panel's own reveal is pinned the same way: hung off `isInspectorOpen` and only on the way open, with no anchor, and waiting `panelTravel` — plus a check that `panelTravel` covers the whole of the 0.16s both roots animate the panel over, since a shorter wait is a measurement taken mid-flight rather than a near miss. Then the arithmetic that keeps the reveal margin free: the inset plus what is left of the spacing is the gutter, and the inset plus what is left of the strip's margin is the strip's margin — both remainders being negative at the current inset, which is why it is asked as a sum |
| `FieldFocusTests` | that a field which opens, opens with the keyboard in it. Nothing in the app writes a `@FocusState` from `onAppear` — the line that shipped three fields unfocused — told apart from the `@AccessibilityFocusState` the phone's drawer sets there on purpose by how the property is declared, so a file nobody has thought about is covered too. Then the other half, without which the rule is met by a field that never focuses at all: the set of files using `focusWhenReady` is the set named in the test. Then what the modifier must do — yield *before* it asks, and not go back to waiting a fixed number of milliseconds |
| `PreferenceBehaviourTests` | the twelve settings added at once, and chiefly that **the default of each leaves the app exactly as it was** — the cheapest way to ship a bug is to move a default while adding the switch that names it, so every default is written out here and cannot change without this test being edited. Then a stored value this build has no case for falling back rather than reading as nothing (what a downgrade leaves), a switch turned *off* being told from one never touched, the rolling and calendar weeks disagreeing where they should, the auto-archive sweep waiting for a card to settle and naming no undo step, and the view being written down whichever way the resume switch is set |
| `SettingsTabTests` | the list Settings divides into, on whichever platform the suite is run: **at most four subjects**, because a pane holding one switch is a row that has been given a tab of its own and everybody pays for it on the way past; the Trash not among them, since it is the user's own work rather than a preference; no two subjects drawn under one name; each glyph resolving as a symbol the system actually has — an unresolved `systemImage` draws nothing and reports nothing, which is a toolbar item that is a word with a hole above it; General first, because both surfaces open on whatever is first and that is a decision rather than an accident of typing order; and the same four on both platforms, the desk's two extra switches being rows inside General rather than a case compiled out on iOS, so `allCases` is the whole truth about what gets drawn and nothing has to remember to filter it |
| `CardProgressTests` | the checklist's fraction and the line drawn to it: that the two come from the same pair of numbers so a card cannot show "2/3" over a half-drawn line, that both cards stack the line inside their own rounded rectangle and clip it there rather than laying it over the corners, that the line survives compact where the fraction does not, and that the fraction sits on the trailing side of the meta row's spacer |
| `BoardSettingsTests` | what the board settings sheet promises before it changes a board: the refuge a trashed column's cards move to being the one `deleteColumn` actually moves them to and the column itself landing in the Trash; the count including archived cards, because the move does; an empty column's warning saying only the part that is still true; that **no** reorder from anywhere to anywhere changes where completed work lands, that adding a column leaves the Done column where it is, and that the Done column refuses every move; plus the shape of the composer — a name and a short, no role, sitting between the working columns and Done — and the board strip no longer ending in a tile |
| `SidebarRoomTests` | iOS only — which of an iPad window's three panels gives way, and when. A 13" in landscape closing nothing whichever is opened, since it holds all four columns at once and is the shape the layout was drawn for; an unmeasured window closing nothing either, because the other way round shuts a panel on the way in; opening a panel on the left collapsing the *editor* first, which on an 11" in landscape is the whole of it — the two left-hand panels fit together perfectly well once the far side has gone; an 11" in portrait, which has room for one, emptying the rest for whichever was asked for; the two on the left still taking turns with the editor already away, since a panel that costs nothing is skipped rather than counted as the answer; a source list the system drew *over* the board not competing at all; opening the editor taking the room from the far side first and from both when one is not enough; the line being exactly the board's own floor; and two properties over every iPad width and every combination of what was open — that what is left always holds the rest and never closes the panel just opened, and that whatever closes for the Inbox leaves a window the panel will actually draw in. `UITests/PadSidebarsTests` presses the buttons |
| `DrawerWidthTests` | iOS only — how wide the phone's drawer is drawn, which is 84% of the screen's **short** edge rather than of the container it is handed: the same width on every phone held either way up; the landscape number not being 84% of the landscape width, which is 734pt of board list over a sliver of board; the ceiling being that device's own portrait width rather than a constant, since a maximum picked once widens the smaller phone on its side; an unmeasured screen falling back to the container, so zero cannot win the `min` and collapse the panel; and a container narrower than the screen still holding the panel |
| `ToolbarFoldTests` | at what width the board header folds its search field into a button, which is arithmetic because the bar's width is whatever the split view left the detail column: the fold happening *before* the row runs out of room rather than after, and leaving the board's name something worth reading; the decision being monotonic in width, so no drag across the line can make it flicker; where the line falls on the shapes real iPads have — a 13" in portrait keeping its field with the board to itself *and* with either column beside it, losing it only when both are out, and an 11" in portrait losing it to the source list alone; each control in the row and the traffic lights' 68pt band moving the line, the capture button included, which is also where the iPad having one and the desk not is pinned; larger type folding sooner and stopping at the chrome caps; and the desk not folding at all, with its own window floor checked to still hold the bar that decision leans on. `UITests/ToolbarFoldTests` presses the button |
| `TrashSurfaceTests` | where the Trash is now that it is not a settings tab: the flag being session state that starts shut and changes nothing about the board, `SettingsView` building no `TrashView` and holding no trash pane, each of the two door-bearing surfaces — the source list on macOS and iPad, the board menu on the phone — raising `isShowingTrash`, and the phone's sheet being presented by the root rather than by the header that opens it, which is a thing a menu cannot do |
| `ScaleTests` | 7.4 — five hundred cards on six boards, thirty columns, twenty-four labels and eleven thousand activity entries, and what each hot path costs on it. Nothing asserts a wall-clock time: every bound is a *ratio* between two timings taken in the same process on the same data, which cancels the machine out and leaves the shape of the algorithm. See **Scale** |
| `FirstRunTests` | 7.5 — a first launch starting on nothing at all rather than on the sample; the picker never standing in front of the test host; the sample offered rather than first; the three starters carrying none of the sample's cards; and then the property over all five templates — folded into the empty board a first launch actually builds, each one satisfies the placement invariant, resolves every label key it wears, mints no duplicate code, has a landing column and a Done column, survives a relaunch card for card, and takes a card added, dated, completed and archived on it. Choosing is one ⌘Z |
| `PackagingTests` | 7.6 — what the *built* bundle carries, read off `Bundle.main`, which under `xcodebuild test` is the app: a marketing version and a numeric build; the version the About panel shows being the one in the plist rather than a second copy of it; `PrivacyInfo.xcprivacy` present, declaring no tracking and no collection, and naming a reason for each required-reason API it touches; the copyright line the macOS About panel reads; `UILaunchScreen` naming a colour rather than being the empty dict that flashes white; every UTI, document type, URL scheme and activity type the code assumes; and the update check's repository, releases page and version comparison |
| `LocalizationTests` | 7.2 — mostly the one property with nothing to observe at runtime, so it reads the source (`SourceTree.swift`, anchored on `#filePath`). Three narrow rules rather than one broad one: every `String(localized:)` carries a translator comment, `Text(verbatim:)` never carries typed words, and the model and store layers — which have no `LocalizedStringKey` position to sit in — hold no prose that is not going into the catalogue. `Text("Delete Task")` is not a violation and is not flagged; a check that flagged two hundred correct call sites would be switched off within the week. Then two that read the *build* instead: the catalogue is compiled into the app at all, and the words that reach `Text` through a view helper are in it — which is the one thing no source scan can see, and is exactly how seven helpers came to take their title as `String` and put five English words on every screen in every language |
| `StarterTemplateTests` | 7.5 from the template's side — five starters offered with the sample among them rather than first; each with a column work can start in and one it finishes in; no two sharing a column id; every card on its own board under a unique code with that board's prefix; every label a card wears shipped by the template that wears it; choosing one filling an empty board with exactly it; and the picker never standing in front of a test host. `UpdateVersionTests` sits beside it: 1.10 newer than 1.9, a `v` prefix that is part of the tag and not of the version, a pre-release suffix ignored, an unparseable tag never newer, and the releases page declared in the bundle |
| `AccessibilityContrastTests` / `AccessibilityAdaptationTests` | 7.1 as arithmetic — every secondary tone's contrast on every surface it is drawn on, the due chip at each urgency in both schemes, each priority's mark being a *shape* of its own, counted off `allCases`, one glyph per tint the chip distinguishes and none for the neutral one, Reduce Motion taking the animation and not the change, and the chrome scale never shrinking anything. Plus the one rule about how the code reads the setting: Differentiate Without Colour is never read negated, because which way round that flag is tested lives in a view body where no value test can reach it. See **Accessibility** |

`SaveContractTests` and `UndoHarnessTests` are hand-written registries, not
reflection: each names every public mutation and asks the same two questions of
it. **Adding a mutation means adding it to both, and bumping the count
`UndoHarnessTests` asserts** — that number is the registry's only defence against
being forgotten, since a mutation nobody listed passes by not being asked.

**Every test uses `BoardStore(file: nil)`, or a `BoardFile` in a temp directory
of its own** — `TestSupport.swift` vends one and tears it down, and everything
file-backed goes through it. Never `BoardFile.default`: that is the user's real
board, so a test that writes there destroys their work, and one that merely reads
it is a test whose result depends on whose machine it runs on. Nothing asserts
against `Date.now` either — the board the suites work from is written out in
literals, because `SeedData` is derived from today and an assertion about it
would mean something different tomorrow.

Phase F added two more of the same shape, because it added two more places a
test can reach the machine it is running on. **A notification test is handed a
fake `TaskNotificationCenter`**, never `NotificationScheduler.shared` — that one
holds `SystemNotificationCenter`, which is the real Notification Centre and
would leave a week of reminders queued on the developer's Mac. And **a
preference test writes to a throwaway `UserDefaults` suite**; the two settings
that go to `.standard` — the appearance override and the sort order — are read,
changed and put back by `PreferenceTests.BorrowedDefaults`, because
`xcodebuild test` launches the app as the test host under its real bundle
identifier and `.standard` there is the developer's own preferences.

## Scale

7.4 asked for numbers before any optimisation, so `ScaleBoard` builds a board
nothing here had been run at — 500 cards on 6 boards, 30 columns, 24 labels,
10,985 activity entries, **2.9MB** of pretty-printed JSON — from a fixed seed, so
two runs build byte-identical boards and a timing that moves is the code moving.

Measured on Apple Silicon, Debug (`-Onone`), which is what the suite runs as:

| path | measured | against | after |
| --- | --- | --- | --- |
| `subscript(id:)`, once per card | 43.4ms | 53µs through a `[TaskItem.ID: Int]` index — **814x** | **6.4x** |
| the same, 100 cards → 500 | **25.8x** | a theoretical 25x: it was quadratic | **5.0x**, which is linear |
| `labels(for:)`, every card's chips | 2.7ms | 590µs through a `[String: LabelDef]` — **4.6x** | **1.1x** |
| `visibleTasks(in:)` × 30 columns | 8µs | 224µs for the one pass that fills the memo — **0.04x** | unchanged |
| a search keystroke, warm | 1.33ms | 3.00ms cold — the haystack memo is **2.26x** | unchanged |
| encoding the board | 51.8ms | 10.4ms at 100 cards — linear, as "the whole board re-encodes" implies | left alone |
| `saveNow()` | 54.1ms | the encode is **96%** of it; the atomic write is 4% | left alone |
| reading it back | 69.5ms | 1.34x the write — decoding allocates what encoding walks | left alone |

Two of the four paths 7.4 names were already fixed in Phase A: the per-column
grouping is memoised on the query, the card count, a revision counter and the
sort order, and the folded search text is memoised per card on that same counter.
The other two were fixed on this evidence, and every bound in `ScaleTests` now
pins a win rather than tolerating a cost.

**`BoardStore.position(of:)`** is the id index, and it is a memo rather than a
maintained structure because `tasks` is written from twenty places and a map
updated at each of them would be wrong the first time somebody added a
twenty-first. Two checks make a memo safe here: a **hit** is believed only while
the position still holds the task it was recorded against, and a **miss** only
while the map was built at the current revision and card count. A mutation that
reorders the array therefore costs a rebuild, never a wrong card — which is the
only failure that would matter, because a card body resolving to some other
card's contents looks like the board scrambling itself. `tasks` is read on every
path, cached or not, so a view that only ever hits the memo still registers its
dependency on the board. The remaining 6.4x over a bare dictionary is that
checking, plus the `@Observable` read.

**`label(forKey:)`** is a `[String: LabelDef]` dropped by `labels`' own `didSet`.
The asymmetry is deliberate: a renamed definition is still findable at its key,
so nothing about a stale label entry gives it away and it has to be invalidated
rather than checked — while `tasks` cannot have a property observer at all,
because one costs the array a copy on every in-place write and the store writes
into `tasks` in loops.

**What was measured and deliberately left alone.** The save path is *not* worth
an incremental or binary format: encoding is 96% of it and already off the main
actor for the debounced write. `saveNow()` — at quit and at backgrounding — is
the only place the 52ms is paid on the main thread, and if that ever matters the
thing to move is quit-time saving, not the format. Reading the board back costs
69.5ms once, at launch, against no deadline.

**The keystroke path (second pass).** The measurements above cover the debounced
write and stop there, and what grew up in front of the debounce is what made the
app feel slow: `scheduleSave()` had accumulated four whole-board passes that ran
*inline* on every mutation — the reminder rebuild, the Spotlight reconcile, and
the record diff behind `pushToSync`, which fetched **every** `StoredTask` row
out of SwiftData and ran `context.save()` on the main actor, per character
typed. All three ride the debounced task now, `saveNow()` runs them before its
synchronous write so quit loses nothing, and a diffed `applyTasks` fetches only
the records it will touch. `aKeystrokeDoesNotWaitForTheRecordStore` pins the
shape: a keystroke with the record store attached against one without, bound at
3x, and the inline apply fails it by an order of magnitude.

The render side had grown the same way, and the same sweep took back: the two
`.fileExporter(document:)` calls built their documents — one a full Markdown
render of the board — on every body pass of the window carrying them, and read
`exportedSnapshot` there, which re-rendered the whole window per keystroke
(documents now render in `fileWrapper`, at Save); `CalendarDay`'s `-` and
`adding(days:)` cost three ICU round-trips each inside every per-task filter
(now integer civil-calendar arithmetic); `board(ofColumn:)` scanned every
board's columns once per task inside those same filters (now an owner map
dropped by `boards`' `didSet`, the `labelsByKey` bargain); a saved-view row's
count filtered *and sorted* the board twice per row per render (now counted,
memoised per revision); `ColumnFlowLayout` measured every card twice per pass
(the placement now reuses a fresh pack's measurements); and each activity row
carried its own minute `TimelineView`, each tick allocating a fresh
`RelativeDateTimeFormatter` (one timeline, one shared formatter).

## Debug launch hooks

`DEBUG` builds read launch arguments so a surface can be opened directly,
without scripting taps:

```sh
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenSheet NW-118
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenDrawer YES
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanTab search
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenSettings YES
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenBoardSettings YES
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenLink simplekanban://new
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanFirstRun YES
xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanSkipFirstRun YES
```

The sheet argument takes either a task's `code` or its UUID, matched
case-insensitively. The link argument takes any `simplekanban://` URL and queues
it exactly as an arriving one is queued, so the four destinations a widget taps
can be driven without a widget — and without `simctl openurl`, which stops to
ask "Open in Simple Kanban?" and needs a tap of its own. It is how the iPad's
capture bug above was found and how the fix was confirmed. The last two are about the starter picker, which otherwise
stands between every one of the others and the board it means to drive: forcing it
also redirects the session to a throwaway file, so a forced first run cannot write
an empty board over a real one. `SeedData` exposes the seed ids as named statics
(`SeedData.dragAndDropTaskID` and friends) so a test can address one directly.

## Language and direction

Every user-facing sentence goes through `String(localized:comment:)` or
`Text(_:comment:)` and lands in `Resources/Localizable.xcstrings`, the String
Catalog `SWIFT_EMIT_LOC_STRINGS` extracts into (786 keys). **The catalogue is
part of the change**: refreshing it after adding strings means building *both*
platforms and merging the compiler's output from both, because half the view code
is behind `#if os(iOS)` and syncing from macOS alone marks every iOS-only string
stale — 131 of them, the first time this was done.

```sh
# One pair of directories per sync, named for *this* sync and removed first.
# A `find /tmp/sk-dd-*` over whatever is lying around sweeps up every build
# anybody has ever left in /tmp, and syncing against a months-old extraction
# marks every string added since as stale.
rm -rf /tmp/sk-sync-mac /tmp/sk-sync-ios
for pair in 'platform=macOS:/tmp/sk-sync-mac' 'generic/platform=iOS Simulator:/tmp/sk-sync-ios'; do
  xcodebuild -project SimpleKanban.xcodeproj -scheme SimpleKanban \
    -destination "${pair%%:*}" -derivedDataPath "${pair##*:}" build
done
# xcstringstool is Xcode's own and is not on the default PATH.
find /tmp/sk-sync-mac /tmp/sk-sync-ios -name '*.stringsdata' -path '*SimpleKanban.build*' \
  | grep -v Tests | sed 's/^/--stringsdata /' | xargs \
  "$(xcode-select -p)/usr/bin/xcstringstool" sync Resources/Localizable.xcstrings
```

The catalog carries an `en` value for every key, equal to the key. That is a
no-op at runtime — the key is the value in the source language — but it is what
makes Xcode compile an `en.lproj/Localizable.strings` into the bundle, and
without a compiled table the accented and right-to-left pseudolanguages have
nothing to work on. Strings left in `state: "new"` are dropped from that table,
so a freshly synced key has to be promoted before it can be seen in a pseudolocale.

**A title only extracts if the parameter it is passed to is a key.** This is the
trap the whole area has, because nothing about it is visible on screen: the
compiler extracts a literal that is converted to `LocalizedStringKey` — including
one handed to a *helper* of your own that takes one — and extracts nothing at all
from a literal passed to a `String` parameter, which is a finished string rather
than a key. Seven small view helpers (`sectionHeader`, `field`, `columnField`,
`fieldName`, `stepButton`, `attributeCard`) took their title as `String`, so
"Boards", "Short", "Move Up", "Move Down" and "No due date" reached the
screen in English whatever the language was. They now take `LocalizedStringKey`.
`??` has the same edge: `.accessibilityValue(text ?? "No due date")` picks the
`StringProtocol` overload and never looks in the catalogue, so the fallback is
built with `String(localized:)` before it gets there.

Two `LocalizationTests` cases read the *compiled* table out of the app the suite
is hosted in, because that is the only place the difference shows: one asserts the
catalogue is in the target at all — it sat in none for a while, and every
`String(localized:)` in the app quietly returned its own key — and one asserts
that the words those helpers draw are in it.

115 of the keys have no `comment:` for the translator. All of them are in view
files, and most are `Button`/`Label` titles, whose initialisers have no comment
parameter — adding one means rewriting the control with an explicit
`label: { Text(_:comment:) }`. `String(localized:)` *does* take one, and the
suite holds that at zero.

**Stored values are not display strings.** The rule the file format has to keep is
that nothing on disk is a word the interface draws, because a board written in one
language has to read in another. `ActivityEntry` stores a `Kind` and renders the
sentence at display time; `Priority` stores `max`/`high`/`medium`/`low` and answers
`displayName` separately (v5 → v6, above); `PhoneTab`, `SavedView` and `BoardSortOrder`
all key on a slug and name themselves in a `switch`. `LabelDef.key`
is the same rule for user content: the key is the stable slug tasks store, the
`name` is what the chip draws.

**Seed copy is translated once, at seed time, and never again.** `BoardColumn`'s
four workflow columns, `LabelDef.seed`'s five labels and every title, note and
sub-task in `SeedData` are `String(localized:)`, so a fresh install comes up in the
user's language. The moment that board exists it is *their* board: nothing
retranslates it, because a card whose title changed itself when the phone's
language did would be the app editing somebody's work. `SeedData.defaultBoard.name`
is the deliberate exception — a made-up product name is a proper noun everywhere.

**Right to left.** There are no absolute x-offsets left in the tree
(`grep -rn '\.offset(x:' Sources/` comes back empty), so the layout mirrors on its
own: leading/trailing padding, `HStack`, `ZStack(alignment: .leading)` and the
drawer's `.transition(.move(edge: .leading))` all follow `layoutDirection`. **Two
values do not, and both flip by hand off `layoutDirection`.** One is a *shadow*
offset — `.shadow(x:)` is a raw coordinate and mirrors nothing — so the drawer
panel's reads the environment and negates itself. The other is `UIRectEdge`,
which is UIKit's and is absolute where SwiftUI's `Edge` is semantic: the edge
swipe's recognizer is handed `.right` in a right-to-left layout and `.left`
otherwise, so it watches the edge the drawer actually comes from.
Left alone it cast the shadow underneath the panel instead of onto the board:
measured across the panel's inner edge, 17 levels of luma in English against 5 in
Arabic.

Sub-task progress is `String(localized: "\(done)/\(total)")` rather than an
interpolated literal for a bidi reason: `2/3` is two numbers around a neutral
separator, so a right-to-left paragraph can reorder it into `3/2`. Going through a
key gives a translator somewhere to put the marks that stop it.

`.textCase(.uppercase)` in `sectionLabelStyle` and `LabelChip` uses the environment
locale, so Turkish gets `İŞ` rather than `IS` and scripts with no case are left
alone. `LabelChip` holds a translated name to one line at `maxNameWidth` and
truncates, so a longer word cannot reflow the row.

## Naming

The product name, bundle identifier and display name live in `project.yml`
(`PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleDisplayName`). The Xcode
project, target and scheme are `SimpleKanban` (no space, so command-line
invocations stay quote-free); the built app is `Simple Kanban.app`.

The wordmark shown in the iOS navigation drawer is in
`Sources/IOS/PhoneNavDrawer.swift`. It is read off `CFBundleDisplayName` and drawn
with `Text(verbatim:)`: a product name is spelled the same in every language, and
a literal in a `Text` would have offered it to a translator as though it were not.

A **board's** name is data rather than a literal. `"Northwind iOS 3.0"` used to be
typed into four view files; it now survives in exactly two places, and
`grep -rn "Northwind" Sources/` is the check that keeps it that way:
`SeedData.defaultBoard`, the board a fresh install is seeded with, and the v4 → v5
migration, which has to name the board it makes for a file written before boards
existed. Every title, sidebar row and drawer row reads `store.activeBoard?.name` —
`Optional`, because deleting the last board is allowed.

## Fonts

Seventeen families are bundled under the SIL Open Font License (see
`Resources/Fonts/OFL-*.txt`) — the faces the twenty themes are set in — and
registered by `FontCatalog` on first use rather than at launch:
`bundledFamilies` is a `static let` whose initialiser does the registering, so it
runs exactly once, under the runtime's own lock, the first time anything asks for
a font. Delete the folder and every theme falls back to a system face of the same
kind.

Fifteen of the seventeen are **variable** fonts, which is what keeps the folder to
5.6 MB and is also why resolving a face is not a matter of writing down a name.
See **Themes ▸ The seventeen faces**.
