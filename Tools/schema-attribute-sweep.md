# Schema attribute sweep — before promoting to production

The companion to `sync-merge-checklist.md`, and it answers a different question.
That one asks *does sync work*. This one asks *is the schema you are about to
freeze complete*.

**Why it is a separate pass.** CloudKit does not take the schema from the model.
`NSPersistentCloudKitContainer` mints a record type the first time a record of
that entity is written, and it mints each **field** the first time that attribute
is written *with a value*. An attribute that was `nil` on every record you
happened to create is an attribute that is not in the Development schema, and so
is not in what you promote.

Nothing breaks immediately. The field appears later, the first time some device
writes it — which is legal, because a production schema is additive. What is lost
is the moment where the shape was still free to change. After promotion it is
permanent: a model type can never be removed and an attribute can never change
type. The point of this sweep is to arrive at that moment having seen every
field, rather than the ones an ordinary afternoon happens to use.

## What is actually at risk

`SyncSchema.swift` declares **51 attributes across 7 models**. Most are
non-optional with a default — `title`, `name`, `roleKey`, `position`, `when` —
and are written on *every* record of their type, so any record at all creates
them. They are not where the risk is.

**20 are optional.** Two of those cannot be written by this build at all (see
*Expected absences*), which leaves **18 that exist only if you go and cause
them**. Those are what Part 1 is for, and the steps that produce them are marked
**load-bearing** below. The unmarked steps are worth doing for realistic data and
to create the record types in the first place, but you can be quick about them.

## How to run it

Run it on **device A** during the two-device checklist rather than as a second
sitting — every write here also travels, so it doubles as sync coverage.

Sync must be on and the build entitled. **A simulator cannot do this:**
`LITTLEKANBAN_CLOUDKIT` is set for `sdk=iphoneos*` only, and a simulator build is
stripped of entitlements regardless, so it reports no container and sync stays
off. A real device or the Mac.

## Part 1 — the exercise

### Boards and columns

1. **Make a board, and pick an SF Symbol for its mark.** — **load-bearing**
   → `StoredBoard.symbol`, plus `.name`, `.createdAt`, `.position`, `.codePrefix`
   `codePrefix` has no interface: `BoardStore` derives it and nothing lets you
   type one. It is non-optional, so it is written on every board regardless.
2. **Make a second board and switch to it.** — **load-bearing**
   → `StoredMeta.activeBoardID`, which is the only optional field here
   `StoredBoard.position` is *not* load-bearing despite looking like it: it is
   non-optional, so every board record carries it whether anything is ever
   reordered or not.
   **Boards do not reorder by dragging**, on either platform — the source list
   is not a `List`, so SwiftUI's `onMove` is unavailable and explicit Move Up /
   Move Down sit on the row's context menu and the View menu instead. See
   `BoardSidebar.swift` and `PhoneNavDrawer.swift`. Reorder if you want the data
   to look real; skip it without consequence for the schema.
3. **Add a third column, and set a WIP limit on it.** — **load-bearing**
   → `StoredColumn.limit`, plus `.name`, `.short`, `.position`, `.roleKey`
   `limit` is the one most likely to be missed: no starter template sets one, so
   unless you do it deliberately the field is never written.

### One card carrying every field

4. **Make a card with a title and a description.**
   → `StoredTask.title`, `.note`, `.code`, `.createdAt`, `.updatedAt`,
   `.priorityKey`; `StoredActivity.kind`, `.when`; and `.boardID` / `.columnID`,
   which are optional but set on any card that lives on a board
5. **Give it a due date.** — **load-bearing** → `StoredTask.dueDay`
6. **Give it a priority other than medium.**
   Not load-bearing — `priorityKey` is non-optional — but a board where every
   card is medium is poor material for the sync scenarios.
7. **Make a label, set explicit light and dark colours, and apply it.** —
   **load-bearing**
   → `StoredLabel.light`, `.dark`; plus `.key`, `.name`, `.position`, and
   `StoredTask.labelKeys`
   A label left on the theme's own rule may never write a stored tone pair, so
   set the colours rather than accepting what it offers.
8. **Add two sub-tasks and tick one.**
   → `StoredSubtask.text`, `.done`, `.position` — all non-optional, so one
   sub-task would do; two and a tick make the checklist scenarios worth running.
9. **Make the card repeating.** — **load-bearing** → `StoredTask.recurrence`
10. **Drag the card to a different place in its column.** — **load-bearing**
    → `StoredTask.position`, which only a manual reorder writes

### The states a card can be in

11. **Capture a card straight to the Inbox, then complete it there.** —
    **load-bearing**
    → `StoredTask.inboxCompletedAt`, and a record with no `boardID` and no
    `columnID`, which is the Inbox's whole shape
12. **Complete a card on the board, then archive it.** — **load-bearing**
    → `StoredTask.archivedAt`

### Board-wide settings

All three are separate fields on the single `StoredMeta` record, each with its
own date. Doing one does not write the other two. All **load-bearing**.

13. **Make a saved view with a rule in it.** → `.viewsJSON`, `.viewsChangedAt`
14. **Save a colour to the palette.** → `.paletteJSON`, `.paletteChangedAt`
15. **Make a theme in the editor and put it in a slot.** → `.themesJSON`,
    `.themesChangedAt`

## Part 2 — verify in the console

<https://icloud.developer.apple.com> → container `iCloud.com.n14395.LittleKanban`
→ **Schema** → **Record Types**, environment set to **Development**.

**Everything is prefixed `CD_`.** The mirror names the record type after the
entity and each field after the attribute, both with a `CD_` prefix — so look for
`CD_StoredTask` carrying `CD_title`, not `StoredTask` carrying `title`. Hunting
for the unprefixed names and finding nothing is the usual first five minutes.

**To-one relationships are Reference fields on the child.** `CD_StoredSubtask`
carries `CD_task`; `CD_StoredColumn` carries `CD_board`. The parent has no field
for the other side — the inverse is what the mirror reads.

The table is exhaustive rather than optimised: the exercise above is the short
path, and this is the safety net. Tick every row.

| Record type | Fields that must be present |
| --- | --- |
| `CD_StoredTask` | `id`, `code`, `boardID`, `columnID`, `title`, `note`, `labelKeys`, `dueDay`, `priorityKey`, `createdAt`, `updatedAt`, `position`, `inboxCompletedAt`, `archivedAt`, `recurrence` |
| `CD_StoredSubtask` | `id`, `text`, `done`, `position`, `task` |
| `CD_StoredActivity` | `id`, `kind`, `when`, `task` |
| `CD_StoredBoard` | `id`, `name`, `symbol`, `createdAt`, `codePrefix`, `position` |
| `CD_StoredColumn` | `id`, `name`, `short`, `roleKey`, `position`, `limit`, `board` |
| `CD_StoredLabel` | `key`, `name`, `light`, `dark`, `position` |
| `CD_StoredMeta` | `id`, `nextSerial`, `themesJSON`, `viewsJSON`, `paletteJSON`, `viewsChangedAt`, `paletteChangedAt`, `themesChangedAt`, `activeBoardID`, `updatedAt` |

A missing field is not a failure of this document — it means the action that
writes it did not happen. Go back and do it rather than promoting without.

### Expected absences

**One** attribute is neither read nor written by this build, so no action in the
app can produce it and its absence is correct:

- `StoredBoard.dot` — v15's board colour. A board's mark is a glyph since v16,
  so there is no colour to derive from one.

It is kept in the model deliberately, so that a build from before v16 syncing
against this one finds the last colour it wrote rather than a board gone
colourless. If such a build ever writes one, the field is created then — an
addition, and therefore legal on a promoted schema. Do not go looking for a way
to make it appear.

**Two neighbours read like the same case and are not.** Both must be *present*:

- `StoredColumn.dot` — a column is still recoloured from board settings, so this
  is written on every column (`BoardSyncStore`'s `record.dot =`) and read back on
  the way in. Only the *board's* colour died in v16. `SyncSchema.swift` used to
  describe this one as "As `StoredBoard.dot`", which was wrong and is now fixed.
- `StoredColumn.roleKey` — nothing reads it since v9, but `BoardSyncStore` still
  writes it on every column so a pre-v9 build finds exactly one Done column, in
  the right place.

## Then promote

Only once every row above is ticked:

1. Record the two-device run in `README.md` § *Sync* — the date, both devices,
   both OS versions.
2. **Deploy Schema Changes**, Development → Production.

One way, and additive only from then on.
