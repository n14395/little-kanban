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
  Model/               TaskItem, BoardColumn, LabelDef, Priority, SeedData
  Store/               BoardStore — all state and mutations
  Theme/               Palette (design tokens), Typography, SwatchColor
  Mac/                 Sidebar, toolbar, board, columns, cards, inspector
  IOS/                 Header, pager, cards, tab bar, drawer, detail sheet
  Shared/              Chips, checklist, label picker, flow layout, hairlines
Resources/
  Fonts/               Manrope + Instrument Serif (OFL), registered at launch
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
| `min-width` on the status segments | Border-box, so the frame wraps the padding; `ViewThatFits` gives the spec's `flex: 1 0 auto` **and** its `overflow-x: auto` fallback |

Two deliberate departures from a literal transcription:

- **Type scales with Dynamic Type.** The spec's pixel sizes are used as points
  but declared `relativeTo:` a text style, so the app honours the user's text
  size. Rendering at the default size is unchanged.
- **Shadows are drawn on shapes, not views.** CSS `box-shadow` affects only the
  box; SwiftUI's `.shadow` also blurs the view's *text*. Every shadow here is
  attached to its background shape.

## What the spec does not define

These are faithful gaps, not oversights — the design has no behaviour for them:

- **Board and view rows are presentational.** "Website refresh", "Support
  triage", "Today", "Upcoming" and friends render exactly as designed but do
  not switch or filter; the spec defines no second board and no view queries.
- **State is in memory.** The board resets to `SeedData` on launch. There is no
  persistence or sync layer in the design (the "Synced just now" footer is
  static text).
- **Due dates are strings** — "Today", "Thu", "Next week" — because the spec's
  urgency colours switch on those exact literals. Swapping `TaskItem.due` for a
  `Date` and deriving the tone is the first real change to make.
- **No delete.** The design provides no affordance for removing a task.

## Debug launch hooks

`DEBUG` builds read launch arguments so a surface can be opened directly,
without scripting taps:

```sh
xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenSheet t1
xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenDrawer YES
xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanTab search
```

## Naming

The product name, bundle identifier and display name live in `project.yml`
(`PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleDisplayName`). The Xcode
project, target and scheme are `SimpleKanban` (no space, so command-line
invocations stay quote-free); the built app is `Simple Kanban.app`.

The wordmark shown in the iOS navigation drawer is in
`Sources/IOS/PhoneNavDrawer.swift`.

## Fonts

Manrope and Instrument Serif are bundled under the SIL Open Font License
(see `Resources/Fonts/OFL-*.txt`) and registered at launch by `FontRegistry`.
Delete the folder and the app falls back to the system faces.
