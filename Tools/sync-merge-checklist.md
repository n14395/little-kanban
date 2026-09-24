# Two-device sync merge test — the checklist

The one thing `SyncStoreTests` and `SyncWiringTests` cannot prove: what two real
devices, through a real CloudKit container, do to each other. Everything below
is driven by hand on **a Mac and a physical iPhone or iPad**, both signed into
the same iCloud account, both running a build signed for
`iCloud.com.n14395.LittleKanban`. Run it before promoting the schema to
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
Console.app (subsystem `com.n14395.LittleKanban`, category `sync`) for the
failure log lines — none of them should appear in a clean run.

| # | Scenario | Do | Expect | Pass? |
|---|----------|----|--------|-------|
| 1 | Create travels | A: new task in the Inbox | Appears in B's Inbox with title, priority, due date intact | |
| 2 | Board travels | B: new board with two columns, a task in each | Appears on A whole — columns in order, tasks placed, nothing in the Inbox | |
| 3 | Disjoint edits | A edits card X's title; B edits card Y's due date (before syncing either) | Both edits on both devices; neither lost | |
| 4 | Same card, different fields | A retitles card X; B sets X's due date | X carries both the new title and the new date on both devices | |
| 5 | Same card, same field | A retitles X "From the Mac"; B retitles X "From the phone" | One title wins on both devices — note which; both agreeing on the same one is the pass | |
| 6 | Move vs edit | A drags X to another column; B retitles X | X is in the new column with the new title, on both | |
| 7 | Delete vs edit | A trashes card X; B retitles X before syncing | The trash **syncs** since `StoredTrash`: X's trash row appears on both devices either way. What the *card* does is the finding to record — B's unsynced retitle can resurrect it beside its own trash row, in which case Restore on that row says "already there" rather than making two of X | |
| 7b | The trash is one bin | A trashes a card; sync both. Then: B restores it; sync both. Then A trashes it again and **B** empties the trash; sync both | After the first sync B's trash shows the row. After the restore the card is back on both boards and both trashes are empty. After Empty Trash the row is gone from both and **stays** gone — an emptied trash that refills from the other device is the failure this row exists for | |
| 8 | Column reorder | A and B reorder the same board's columns differently, then sync | Both devices converge on the same order | |
| 8b | Column settings travel | A: rename a column, recolour it, and give it a WIP limit | All three arrive on B — the colour since `StoredColumn.dot` went live, the limit since `StoredColumn.limit`. A build from before either reads the column plain and must not error | |
| 9 | Offline batch | B in Airplane Mode: add two tasks, complete one, retitle another. A edits meanwhile. Reconnect B | The union: all of B's edits and all of A's, nothing dumped into the Inbox | |
| 10 | Sub-tasks merge by id | A ticks one sub-task of X; B adds a new sub-task to X | X carries both — the tick and the new row — on both devices, and X's history holds both devices' entries. **The new-row half used to fail**: the orphan sweep read a checklist row the pushing device had not heard of as one it had deleted, so any edit to X from the other side threw the addition away | |
| 11 | Labels and views | A makes a label and applies it; B makes a saved view | Both arrive on the other device; the label keeps its colour, the view its rule. **The view half of this row did not work until v15** — the records had nowhere to put a saved view, and the read handed back the seeded seven, which the launch then adopted over the user's own | |
| 12 | Fresh device import | Delete the app from B, reinstall, launch | The whole board arrives; while it is arriving nothing is shown unfiled, and after it settles nothing is in the Inbox that was not before (the `isAwaitingCompleteSync` path) | |
| 13 | **Fresh device does not empty A** | As 12, and while B is still filling: choose a starter at the first-run picker, make a board, make a label. Then check **A** | A still has every board, card and label it had. This is the regression that emptied two machines from one install — see DESIGN.md § *A store that has not been filled yet is not an empty one either* | |
| 14 | The first session survives | As 12: choose a starter on B, add a card to it, quit B, relaunch B | The card and the chosen board are both still there, and both reach A. B's first session used to be written to `board.json` alone and thrown away by its own second launch | |
| 15 | **The upgrade keeps what was there** | Before updating either device: make a saved view and save a colour on A, and a *different* view and colour on B. Update both to this build. Launch A, sync, then launch B and sync | Both devices end up with **all four** — two views and two colours. This is the undated merge: neither list has a date, so neither is allowed to win. Losing either half is the failure this row exists for | |
| 15b | **Two new views on two devices, both dated** | With both devices settled on this build: make a new view on A and a *different* new view on B, before syncing either. Then sync both | Both views on both devices. This is the *dated* half of 15 — the whole-list rule alone deletes whichever saved second, and the per-item merge with its watermark is what keeps them; see DESIGN.md § *The three lists CloudKit cannot merge* | |
| 16 | The newer edit wins | After 15, with both devices settled: rename a view on A, sync; then rename the *same* view on B, sync; then sync A again | B's name stands on both, because B's edit is the later one. Then do it the other way round and check the answer flips | |
| 17 | A theme travels | A: make a theme in the editor and put it in the light slot. Sync, then pull on B — **no relaunch** | B has the theme in its list on the pull: the theme *list* arrives live since v18, like the views and the palette. Which slot B is *showing* stays B's own until B's next launch — a device does not repaint because another one did | |
| 17b | **A theme crosses an unrelated sync** | B: make a theme. Before it lands on A, add a card on B and pull on A (so A merges the card first). Then pull on A again once the theme has had time to cross | The theme arrives anyway. This is the watermark standing at the stamp it consumed rather than the clock — stamped `.now`, the unrelated merge ran the watermark past the crossing theme and the rule read it as deleted, which was scenario 17's second way of failing | |
| 18 | **A new board travels, and is not eaten** | B: make a board with two columns and put a card on it straight away. Do not touch A until both have settled | The board and the card appear on A. Then check **B**: the board is still there. The failure is the board vanishing from both a moment after it was made — a read taken while it was still arriving became the diff base, and the next save called the difference a deletion | |
| 19 | **Skew never deletes** | Get both devices settled, then on B: delete the app, reinstall, and *immediately* — before the board arrives — make a board and a label. Sync everything | Nothing already on A is deleted, ever. B ends with the account's boards **plus** what it made; any duplicate the race minted is deleted once, by hand, on one device, and stays gone everywhere | |
| 20 | The picker yields | Delete the app from B, reinstall, launch, and **wait** at the first-run picker without choosing | The picker dismisses itself when the account's board arrives; no starter is folded in over it | |
| 21 | **Sync Now fetches** | Quit nothing. Add a card on B; within a few seconds press Sync Now on A (or pull a column) | The card appears under the spinner, without relaunching A. This is the reopen-the-container fetch — before it, the button only read a store the mirror had not refilled | |
| 22 | Push latency | With both apps foreground: add a card on B, touch nothing | It appears on A within seconds — not minutes. Minutes again means the push entitlement regressed: check `com.apple.developer.aps-environment` in the macOS entitlements | |
| 23 | **One of each** | After 13, on both devices: count the columns on every board, then open a card with a checklist and its activity | Each column, sub-task and entry appears **once**, and still does after a few more edits and syncs. The duplicate that grew on every save is what `BoardSnapshot.settlingDuplicates()` closes — see DESIGN.md § *One of each* | |
| 24 | A repeat travels, and spawns once | A: make a repeating card, sync, then complete it on A. Check B after both settle | B shows the completed card in Done **and its spawn, exactly once** — the rule rides `StoredTask.recurrence` and the spawn is minted on the device that completed, so a second copy appearing means both devices spawned. Note the finding if B completes the *same* recurring card before A's completion arrives: two spawns from two completions is the known race to record, not silent loss | |

Then the sanity pass, on both devices: every board's column counts match the
other device, no duplicate cards anywhere, the Inbox holds exactly what it held
before the run plus what the run put there. That last one is regression `6c51d45`
— the bug that sent every task on every board back to the Inbox — and it is the
single most important line on this page.

**Notes worth writing down while it is fresh:** how long a push took to arrive
unprompted (macOS remote-change notifications can be slow); anything Settings ▸
Sync said that surprised you; and scenario 5's winner. All three shared lists —
views, colours, the theme *list* — arrive live on a pull since v18; the only
thing that waits for a launch is which theme a device is *showing*, because a
merge deliberately does not repaint the device it lands on.

Rows 15 to 17b are the three shared lists, which CloudKit cannot merge for us
because each is one blob in one record — see DESIGN.md § *The three lists
CloudKit cannot merge*. They are the rows most worth running twice, in both
directions: every other scenario here has a per-record clock behind it, and
these three have only the rule and its watermark.

## Recording the result

When the run is clean, add a line to `README.md` § *Sync* naming the date, the
two devices and their OS versions — the section currently records no two-device
run, and "covered by tests that by construction cannot prove this" is the gap
this checklist closes. Then, and only then, promote the schema:

1. <https://icloud.developer.apple.com> ▸ container `iCloud.com.n14395.LittleKanban`.
2. Check the **Development** schema lists every record type `SyncSchema.swift`
   declares (StoredMeta, StoredBoard, StoredColumn, StoredLabel, StoredTask,
   StoredSubtask, StoredActivity, StoredTrash) with their fields. **This check
   is load-bearing**: the mirror materialises a record type or field in the
   development schema on the first *write* of it, so a run that never trashed
   a card, never made a repeating card and never recoloured a column leaves
   `StoredTrash`, `recurrence` and `dot` out of the schema — they would not
   promote, and a production client cannot add them later. Rows 7–7b, 8b and
   24 are what write them; anything missing from the dashboard means a row
   was skipped.
3. **Deploy Schema Changes** from Development to **Production**.

Promotion is one-way and the production schema is additive-only from then on: a
model type can never be removed and an attribute can never change type. That
rule already governs `SyncSchema.swift` (see DESIGN.md § *What CloudKit will not
do for you*), but promotion is the moment it becomes binding.
