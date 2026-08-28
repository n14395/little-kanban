# Two-device sync merge test — the checklist

The one thing `SyncStoreTests` and `SyncWiringTests` cannot prove: what two real
devices, through a real CloudKit container, do to each other. Everything below
is driven by hand on **a Mac and a physical iPhone or iPad**, both signed into
the same iCloud account, both running a build signed for
`iCloud.com.n14395.SimpleKanban`. Run it before promoting the schema to
production, and again after any change to `SyncSchema.swift` or the merge paths
in `BoardStore`/`BoardSyncStore`.

**This runs against your real container and your real board.** Before starting:
Settings ▸ Data ▸ Export board… on the Mac, and keep the file somewhere safe.
The rolling backups exist too, but an export you chose the location of is the
one you can find.

## How to read the table

*A* is the Mac, *B* is the iPhone/iPad — swap roles for a second pass if time
allows. After each action, sync both sides deliberately rather than waiting:
**Sync Now** in the Mac status bar, pull past the top of a column on the phone.
CloudKit pushes can take from seconds to minutes; a scenario only *fails* when
the state is still wrong after both sides have synced and settled. Watch
Console.app (subsystem `com.n14395.SimpleKanban`, category `sync`) for the
failure log lines — none of them should appear in a clean run.

| # | Scenario | Do | Expect | Pass? |
|---|----------|----|--------|-------|
| 1 | Create travels | A: new task in the Inbox | Appears in B's Inbox with title, priority, due date intact | |
| 2 | Board travels | B: new board with two columns, a task in each | Appears on A whole — columns in order, tasks placed, nothing in the Inbox | |
| 3 | Disjoint edits | A edits card X's title; B edits card Y's due date (before syncing either) | Both edits on both devices; neither lost | |
| 4 | Same card, different fields | A retitles card X; B sets X's due date | X carries both the new title and the new date on both devices | |
| 5 | Same card, same field | A retitles X "From the Mac"; B retitles X "From the phone" | One title wins on both devices — note which; both agreeing on the same one is the pass | |
| 6 | Move vs edit | A drags X to another column; B retitles X | X is in the new column with the new title, on both | |
| 7 | Delete vs edit | A trashes card X; B retitles X before syncing | Note the outcome on both sides. The trash is local to each device, so a resurrect-vs-stay-gone disagreement here is a finding to record, not necessarily a failure | |
| 8 | Column reorder | A and B reorder the same board's columns differently, then sync | Both devices converge on the same order | |
| 9 | Offline batch | B in Airplane Mode: add two tasks, complete one, retitle another. A edits meanwhile. Reconnect B | The union: all of B's edits and all of A's, nothing dumped into the Inbox | |
| 10 | Sub-tasks merge by id | A ticks one sub-task of X; B adds a new sub-task to X | X carries both — the tick and the new row — on both devices | |
| 11 | Labels and views | A makes a label and applies it; B makes a saved view | Both arrive on the other device; the label keeps its colour, the view its rule | |
| 12 | Fresh device import | Delete the app from B, reinstall, launch | The whole board arrives; while it is arriving nothing is shown unfiled, and after it settles nothing is in the Inbox that was not before (the `isAwaitingCompleteSync` path) | |

Then the sanity pass, on both devices: every board's column counts match the
other device, no duplicate cards anywhere, the Inbox holds exactly what it held
before the run plus what the run put there. That last one is regression `6c51d45`
— the bug that sent every task on every board back to the Inbox — and it is the
single most important line on this page.

**Notes worth writing down while it is fresh:** how long a push took to arrive
unprompted (macOS remote-change notifications can be slow); anything Settings ▸
Sync said that surprised you; and scenario 5's winner. Themes are expected to
arrive **at the next launch**, not live — a merge deliberately does not repaint
the device it lands on.

## Recording the result

When the run is clean, add a line to `README.md` § *Sync* naming the date, the
two devices and their OS versions — the section currently records no two-device
run, and "covered by tests that by construction cannot prove this" is the gap
this checklist closes. Then, and only then, promote the schema:

1. <https://icloud.developer.apple.com> ▸ container `iCloud.com.n14395.SimpleKanban`.
2. Check the **Development** schema lists every record type `SyncSchema.swift`
   declares (StoredMeta, StoredBoard, StoredColumn, StoredLabel, StoredTask,
   StoredSubtask, StoredActivity) with their fields — first run initialised it.
3. **Deploy Schema Changes** from Development to **Production**.

Promotion is one-way and the production schema is additive-only from then on: a
model type can never be removed and an attribute can never change type. That
rule already governs `SyncSchema.swift` (see README § *What CloudKit will not
do for you*), but promotion is the moment it becomes binding.
