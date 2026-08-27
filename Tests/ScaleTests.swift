import Foundation
import Testing
@testable import Simple_Kanban

/// Somewhere for a measured value to go that the optimiser cannot see through.
///
/// Every hot path here is a read whose result is thrown away, and a read whose
/// result is thrown away is a read the compiler may delete — which is how a
/// performance test comes to measure an empty loop and pass forever.
nonisolated(unsafe) var scaleSink: Int = 0

/// A stopwatch built for comparisons rather than for absolute numbers.
///
/// **Nothing here asserts a wall-clock time.** A millisecond budget measured on
/// this laptop is a different budget on a busy CI box and a different one again
/// on the iOS simulator, so a suite written that way is either flaky or so slack
/// it can never fail. Every assertion below is a *ratio* between two timings
/// taken in the same process, seconds apart, on the same data — which cancels
/// the machine out and leaves the shape of the algorithm.
enum Bench {
    /// The best of `rounds`. The minimum is the closest estimate of the work
    /// itself; a mean measures whatever else the machine was doing.
    static func best(rounds: Int = 9, _ body: () -> Void) -> Double {
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<rounds {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start)
            if elapsed < best { best = elapsed }
        }
        return max(best, 1)
    }

    /// `subject` as a multiple of `baseline`, both best-of-N.
    static func ratio(
        _ subject: () -> Void, over baseline: () -> Void, rounds: Int = 9
    ) -> Double {
        // Warm both sides before either is timed: the first pass over a 500-card
        // board pays for faulting it in, and whichever side ran first would wear
        // that cost.
        subject()
        baseline()
        let a = best(rounds: rounds, subject)
        let b = best(rounds: rounds, baseline)
        return a / b
    }
}

/// What five hundred cards cost.
///
/// 7.4 names four suspects — `subscript(id:)`, `labels(for:)`, `visibleTasks`
/// re-filtered per column, and the whole-board re-encode on every save — and
/// says to measure before touching any of them. These are the measurements,
/// written as bounds that hold at the numbers observed and would not hold if
/// the shape of any of them got worse.
///
/// Two of the four were already fixed in Phase A (the per-column grouping and
/// the search haystack) and two were fixed on this evidence afterwards
/// (`position(of:)` and the label map). Every bound below now pins a win rather
/// than tolerating a cost: the number each was written against, before and
/// after, is in its comment, and README's **Scale** section has them together
/// with the one suspect that was measured and deliberately left alone.
@MainActor
@Suite struct ScaleTests {
    // MARK: The fixture itself

    /// The board is the size it claims to be, in every dimension that matters
    /// to a timing below. A generator that quietly stopped producing activity
    /// entries would make the save measurement pass by having nothing to encode.
    @Test func theScaleBoardIsActuallyLarge() {
        #expect(ScaleBoard.tasks.count == 500)
        #expect(ScaleBoard.boards.count == 6)
        #expect(ScaleBoard.allColumns.count == 30)
        #expect(ScaleBoard.labels.count == 24)
        #expect(ScaleBoard.activityCount > 8_000, "the activity histories are the bulk of the file")
        // `isUnfiled` reads the *placement*, which only the store writes — so
        // the Inbox is counted on a store rather than on the array it was built
        // from, where every card is unfiled until it is placed.
        #expect(ScaleBoard.tasks.count { $0.columnID == nil } == 50, "the Inbox has depth")
        #expect(ScaleBoard.tasks.count { $0.isArchived } == 20, "the Archive has depth")
        #expect(Set(ScaleBoard.tasks.map(\.id)).count == 500, "ids collide")
        #expect(Set(ScaleBoard.tasks.map(\.code)).count == 500, "codes collide")
    }

    /// The store adopts all five hundred — `placed(_:on:)` drops a card whose
    /// column no board has, and a fixture that tripped that would be measuring
    /// a board of some other size.
    @Test func theStoreAdoptsTheWholeBoard() {
        let store = ScaleBoard.store()
        #expect(store.tasks.count == 500)
        #expect(store.inboxCount == 50 - store.tasks.count { $0.isUnfiled && $0.isArchived })
        #expect(store.totalCount == 480)
    }

    // MARK: `subscript(id:)` — a map, and called per row

    /// Resolving every card by id, against the same work done through a
    /// dictionary built once.
    ///
    /// The baseline *is* the `[TaskItem.ID: Int]` index 7.4 asks for, doing the
    /// identical job on the identical data, so this measures the store against
    /// the best it could possibly do. It scanned: **814x** — 43.4ms against
    /// 53µs. `BoardStore.position(of:)` landed the index and it is now **6.4x**,
    /// which is the memo's own overhead — one `@Observable` read of `tasks` and
    /// the check that keeps a stale position from being believed — on top of a
    /// lookup the baseline does bare.
    ///
    /// The bound is 15x rather than 6.5x because the baseline is a few
    /// microseconds and a ratio taken against it is noisy; a return to the scan
    /// puts this back in the hundreds.
    @Test func resolvingEveryCardByIdCostsAboutADictionaryLookup() {
        let store = ScaleBoard.store()
        let ids = store.tasks.map(\.id)
        var index: [TaskItem.ID: Int] = [:]
        for (offset, task) in store.tasks.enumerated() { index[task.id] = offset }

        let cost = Bench.ratio({
            for id in ids where store[id] != nil { scaleSink &+= 1 }
        }, over: {
            for id in ids where index[id] != nil { scaleSink &+= 1 }
        })

        #expect(cost < 15, "subscript(id:) costs \(cost)x a dictionary — the index is gone")
    }

    /// The same claim stated as growth, which needs no baseline at all: a
    /// linear lookup done once per card is quadratic in the card count, so five
    /// times the cards would be twenty-five times the work — and a constant-time
    /// one done once per card is five.
    ///
    /// It was **25.8x** for 100 → 500 against a theoretical 25. With the index
    /// it is **5.02x** against a theoretical 5. The bound is 8x, which no
    /// quadratic lookup can get under.
    @Test func resolvingEveryCardByIdGrowsWithTheBoardNotItsSquare() {
        let small = ScaleBoard.store(taskCount: 100)
        let large = ScaleBoard.store(taskCount: 500)
        let smallIDs = small.tasks.map(\.id)
        let largeIDs = large.tasks.map(\.id)

        let growth = Bench.ratio({
            for id in largeIDs where large[id] != nil { scaleSink &+= 1 }
        }, over: {
            for id in smallIDs where small[id] != nil { scaleSink &+= 1 }
        })

        #expect(growth < 8, "five times the board costs \(growth)x — the lookup is scanning again")
    }

    /// The memo has to be *right*, and it memoises an array that twenty
    /// mutations write to — so this rearranges the board every way that moves a
    /// card and asks, after each, whether every id still resolves to its own.
    ///
    /// The failure it exists for is silent and severe: a stale position hands a
    /// card body some other card's contents, and the board looks like it
    /// scrambled itself. `position(of:)` is written so that cannot happen
    /// without the map being rebuilt first; this is that claim, driven.
    @Test func everyIdResolvesToItsOwnCardAfterTheBoardIsRearranged() {
        let (store, undo) = TestBoard.undoing()
        let doing = BoardColumn.inProgress.id
        let backlog = BoardColumn.backlog.id

        func check(_ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
            for (offset, task) in store.tasks.enumerated() {
                #expect(store.position(of: task.id) == offset,
                        "\(task.code) is not at \(offset) after \(what)", sourceLocation: sourceLocation)
                #expect(store[task.id]?.id == task.id,
                        "\(task.code) resolves to another card after \(what)", sourceLocation: sourceLocation)
            }
        }

        check("the board was built")
        step(undo) { store.move(TestBoard.widget, to: doing) }
        check("a card was filed onto a board")
        step(undo) { store.move(TestBoard.cafe, to: backlog, before: TestBoard.dragDrop) }
        check("a card was reordered inside its column")
        var added = TaskItem.ID()
        step(undo) { added = store.addTask(to: backlog, title: "Later") }
        check("a card was added")
        step(undo) { _ = store.deleteTask(TestBoard.sync) }
        #expect(store[TestBoard.sync] == nil, "a deleted card still resolves")
        check("a card was deleted")

        // The wholesale replacement `apply` does is the path a memo over the
        // array is likeliest to survive by accident: the count comes back the
        // same and every position moves.
        undo.undo()
        #expect(store[TestBoard.sync]?.id == TestBoard.sync, "undo brought the card back where the map cannot see it")
        check("the delete was undone")
        undo.redo()
        check("the delete was redone")
        step(undo) { store.archive(added) }
        check("a card was archived")
        #expect(store[added]?.isArchived == true)
    }

    // MARK: `labels(for:)` — a linear lookup per label per card

    /// Every card's chips resolved, against a dictionary doing the same.
    ///
    /// It scanned, with 24 definitions and up to four keys a card: **4.6x** —
    /// 2.7ms against 590µs. Small beside the id scan, because the label list is
    /// short and most cards carry one or two keys, but it is paid per chip per
    /// card per render, which is the busiest loop on the board. `label(forKey:)`
    /// now reads a map dropped by `labels`' own `didSet`, and it is **1.14x**.
    /// The bound is 3x.
    @Test func resolvingEveryCardsChipsIsALinearScanPerChip() {
        let store = ScaleBoard.store()
        let tasks = store.tasks
        let byKey = Dictionary(uniqueKeysWithValues: store.labels.map { ($0.key, $0) })

        let cost = Bench.ratio({
            for task in tasks { scaleSink &+= store.labels(for: task).count }
        }, over: {
            for task in tasks { scaleSink &+= task.labelKeys.compactMap { byKey[$0] }.count }
        })

        #expect(cost < 3, "labels(for:) costs \(cost)x a dictionary lookup — the map is gone")

        // And it still resolves the right chips. A timing is satisfied by a
        // `labels(for:)` that hands back the whole vocabulary — which is both
        // wrong and *faster*, so the bound above cannot be the only claim.
        for task in tasks {
            #expect(store.labels(for: task).map(\.key) == task.labelKeys.filter { byKey[$0] != nil },
                    "\(task.code) wears \(store.labels(for: task).map(\.key)) for keys \(task.labelKeys)")
        }
        let bare = tasks.filter { $0.labelKeys.isEmpty }
        #expect(!bare.isEmpty, "the fixture has no unlabelled card to ask about")
        #expect(bare.allSatisfy { store.labels(for: $0).isEmpty },
                "a card with no labels was given some")
    }

    // MARK: What Phase A already fixed — pinned so it stays fixed

    /// Thirty columns' worth of cards must cost about one pass over the board,
    /// not thirty.
    ///
    /// `visibleTasks(in:)` reads a grouping memoised on the query, the card
    /// count, the revision counter and the sort order. Reverting it to
    /// "filter `visibleTasks` by column" would multiply this by the column
    /// count. Observed: **0.04x** one `visibleTasks` pass — thirty columns cost
    /// 8µs between them against 224µs for the pass that filled the memo. The
    /// bound is 6x, which still fails a board that regrouped even five times.
    @Test func everyColumnsCardsCostOnePassOverTheBoard() {
        let store = ScaleBoard.store()
        let columnIDs = ScaleBoard.allColumns.map(\.id)

        // The yardstick is a literal pass over the board, written out here.
        // It was `searchResults`, back when that *was* an honest pass — it is
        // memoised now, and a baseline that costs nothing fails every subject.
        let cost = Bench.ratio({
            for id in columnIDs { scaleSink &+= store.visibleTasks(in: id).count }
        }, over: {
            scaleSink &+= store.tasks.count { !$0.isArchived }
        })

        #expect(cost < 6, "thirty columns cost \(cost)x a single pass — the grouping memo is gone")
    }

    /// And the memo has to survive an edit *elsewhere* being made and the
    /// grouping being asked for again — it keys on a revision counter, so a
    /// mutation invalidates it exactly once rather than never.
    @Test func theGroupingMemoIsRebuiltAfterAnEditAndNotBefore() throws {
        let store = ScaleBoard.store()
        let column = ScaleBoard.allColumns[0].id
        let before = store.visibleTasks(in: column).map(\.id)
        #expect(store.visibleTasks(in: column).map(\.id) == before)

        let moving = try #require(store.visibleTasks(in: column).first?.id)
        store.move(moving, to: ScaleBoard.allColumns[1].id)
        let after = store.visibleTasks(in: column).map(\.id)
        #expect(after.count == before.count - 1, "the grouping is serving a stale memo")
    }

    /// Typing into the search field re-filters the whole board on every
    /// keystroke. The folding is memoised per card, so the second keystroke
    /// must not pay for folding five hundred cards again.
    ///
    /// Observed: the first pass over a cold board costs **2.3x** a warm one, so
    /// folding is a little over half of what a search pass does and the memo
    /// takes all of it off every keystroke after the first. The bound is on the
    /// warm side — a warm pass must stay under two thirds of a cold one —
    /// because that is the direction a regression goes: dropping the memo makes
    /// every pass a cold one and the ratio falls to 1.
    @Test func aSecondKeystrokeDoesNotRefoldTheWholeBoard() {
        // A cold pass can only be measured once per store, so the best of five
        // fresh ones stands in for the best-of-N every other timing here uses.
        // Built up front, outside the clock, so the allocation is not in it.
        let cold = (0..<5).map { _ -> BoardStore in
            let store = ScaleBoard.store()
            store.query = "scroller"
            return store
        }
        let coldCost = cold.map { store in
            Bench.best(rounds: 1) { scaleSink &+= store.searchResults.count }
        }.min() ?? 0

        let warm = ScaleBoard.store()
        warm.query = "scroller"
        _ = warm.searchResults
        let warmCost = Bench.best(rounds: 9) {
            warm.query = "scroller"
            scaleSink &+= warm.searchResults.count
        }

        #expect(warmCost < coldCost * 2 / 3,
                "a warm search pass costs only \(coldCost / warmCost)x less than a cold one — the fold is not memoised")
    }

    /// The memo is keyed on a monotonic revision rather than on `updatedAt`, so
    /// two edits inside one clock tick cannot leave a card matching text it no
    /// longer contains. Five hundred cards makes that collision likely rather
    /// than theoretical.
    @Test func editingACardChangesWhatTheSearchFinds() {
        let store = ScaleBoard.store()
        let id = ScaleBoard.taskID(0)
        store.query = "zzzunlikely"
        #expect(store.searchResults.isEmpty)

        store.beginEditing(.title, on: id, scope: .desk)
        store.setText("zzzunlikely marker", field: .title, on: id)
        store.endEditing(.title, on: id, scope: .desk)

        #expect(store.searchResults.map(\.id) == [id], "the haystack memo is stale")
    }

    // MARK: The save path

    /// The whole board re-encodes on every debounced save. That is the cost
    /// 7.4 names, and it is real: five hundred cards carrying nine thousand
    /// activity entries is a megabyte of pretty-printed JSON.
    ///
    /// What is asserted is that the cost is in the *encode*, not in the store —
    /// because that decides which fix is worth doing. Encoding is already off
    /// the main actor for the debounced path (`scheduleSave` hands it to a
    /// detached task); the number below is what an incremental or binary format
    /// would have to beat, and what `saveNow()` — which is synchronous, at quit
    /// and at backgrounding — pays on the main thread.
    @Test func theWholeBoardReEncodesOnEverySave() throws {
        let snapshot = ScaleBoard.snapshot()
        let data = try BoardFile.encoder().encode(snapshot)
        // 2.9MB of pretty-printed JSON, nearly eleven thousand activity entries
        // of it. That is what every debounced save re-encodes.
        #expect(data.count > 2_000_000, "the fixture is too small to say anything about save cost")

        // Encoding a hundred cards against encoding five hundred: linear in the
        // board, which is what "the whole board re-encodes" means. Observed
        // 4.98x — 51.8ms against 10.4ms. The bound is 12x, which a super-linear
        // encoder would miss.
        let small = ScaleBoard.snapshot(taskCount: 100)
        let growth = Bench.ratio({
            scaleSink &+= (try? BoardFile.encoder().encode(snapshot).count) ?? 0
        }, over: {
            scaleSink &+= (try? BoardFile.encoder().encode(small).count) ?? 0
        }, rounds: 5)

        #expect(growth < 12, "encoding grows \(growth)x for five times the board")
    }

    /// A keystroke's synchronous cost with the record store attached, against
    /// the same keystroke without one: the two must cost about the same,
    /// because everything O(board) — the record diff with its fetch behind it,
    /// the reminder rebuild, the Spotlight pass — rides the debounce now
    /// rather than running inline in `scheduleSave`.
    ///
    /// This is the regression that made typing feel slow: each character typed
    /// was diffing every task, then fetching every `StoredTask` row out of
    /// SwiftData on the main actor, in front of the next frame. The reminder
    /// and Spotlight halves cannot be measured here — they are test-disabled —
    /// but they moved inside the same task, so the record store stands in for
    /// the lot. The bound is 3x; the inline apply measured well past it.
    @Test func aKeystrokeDoesNotWaitForTheRecordStore() throws {
        let syncedTemp = TempBoard()
        let bareTemp = TempBoard()
        let synced = ScaleBoard.store(taskCount: 500, file: syncedTemp.file,
                                      sync: try BoardSyncStore.inMemory())
        let bare = ScaleBoard.store(taskCount: 500, file: bareTemp.file)
        // The first apply writes every record (`previous == nil`); it happens
        // here, outside the clock, the way a session's first save pays it.
        synced.saveNow()
        bare.saveNow()
        let id = ScaleBoard.taskID(0)

        var stroke = 0
        let cost = Bench.ratio({
            for _ in 0..<20 {
                stroke += 1
                synced.setText("typed \(stroke)", field: .title, on: id)
            }
        }, over: {
            for _ in 0..<20 {
                stroke += 1
                bare.setText("typed \(stroke)", field: .title, on: id)
            }
        }, rounds: 5)

        #expect(cost < 3, "a keystroke costs \(cost)x with the record store attached — the apply is inline again")
    }

    /// A synchronous save of a 500-card board, end to end, against encoding it
    /// alone: the atomic write is not where the time goes, so a fix aimed at
    /// the filesystem would be aimed at the wrong half.
    ///
    /// Observed: `saveNow()` is 54.1ms against 51.8ms to encode — the atomic
    /// write is **4%** of it, and the encode is the other 96%. The bound is 6x,
    /// loose enough for a simulator's filesystem.
    @Test func savingIsDominatedByEncodingRatherThanByWriting() {
        let temp = TempBoard()
        let store = ScaleBoard.store(file: temp.file)
        let snapshot = ScaleBoard.snapshot()

        let cost = Bench.ratio({
            store.saveNow()
        }, over: {
            scaleSink &+= (try? BoardFile.encoder().encode(snapshot).count) ?? 0
        }, rounds: 5)

        #expect(cost < 6, "the write costs \(cost)x the encode — the encode is not the bottleneck")
        #expect(temp.exists)
    }

    /// A round trip through the file at this size: what a relaunch pays, and
    /// what the migration chain would pay per step.
    ///
    /// Reading is the slower half — 69.5ms against 51.8ms to write, because
    /// decoding allocates every task, sub-task and activity entry rather than
    /// walking ones that already exist. It is paid once, at launch, off no
    /// deadline; the bound is here so that stays true.
    @Test func aFiveHundredCardBoardRoundTripsThroughTheFile() throws {
        let temp = TempBoard()
        let store = ScaleBoard.store(file: temp.file)
        store.saveNow()

        let read = try temp.snapshot()
        #expect(read.tasks.count == 500)
        #expect(read.boards.count == 6)
        #expect(read.tasks.reduce(0) { $0 + $1.activity.count } == ScaleBoard.activityCount)

        let bytes = try temp.bytes()
        let snapshot = ScaleBoard.snapshot()
        let cost = Bench.ratio({
            scaleSink &+= (try? BoardFile.decode(bytes).snapshot.tasks.count) ?? 0
        }, over: {
            scaleSink &+= (try? BoardFile.encoder().encode(snapshot).count) ?? 0
        }, rounds: 5)
        #expect(cost < 4, "reading the board back costs \(cost)x writing it")
    }

    // MARK: The counts every surface draws

    /// The sidebar draws a count per board and one for the Inbox, the toolbar
    /// draws a total, and each is its own pass over five hundred cards. Seven
    /// passes is what the board costs to draw its own chrome — pinned as a
    /// multiple of one pass so the shape is visible if a count starts doing
    /// something worse than counting.
    ///
    /// Observed: **8.5x** one pass, which is exactly the number of counts —
    /// one total, one Inbox and one per board. The bound is 20x.
    @Test func theSidebarsCountsAreOnePassOverTheBoardEach() {
        let store = ScaleBoard.store()
        let boardIDs = store.boards.map(\.id)

        let cost = Bench.ratio({
            scaleSink &+= store.totalCount
            scaleSink &+= store.inboxCount
            for id in boardIDs { scaleSink &+= store.taskCount(for: id) }
        }, over: {
            scaleSink &+= store.totalCount
        })

        #expect(cost < 20, "the chrome costs \(cost)x a single count")
    }

    /// Bulk selection over the whole board. `selectedTasks` filters the array
    /// against the set, which is one pass however large the selection is — the
    /// shape that must not become a lookup per selected id.
    @Test func selectingEveryCardIsOnePassOverTheBoard() {
        let store = ScaleBoard.store()
        store.selectAllVisible(today: ScaleBoard.today)
        // ⌘A takes the surface on screen, which is the active board's columns —
        // not every card on the file.
        #expect(store.selectionCount == store.tasks.count {
            $0.boardID == store.activeBoardID && !$0.isArchived
        })
        #expect(store.selectionCount > 50, "the active board is too small to measure on")

        let cost = Bench.ratio({
            scaleSink &+= store.selectedTasks.count
        }, over: {
            scaleSink &+= store.tasks.count { !$0.isArchived }
        })

        #expect(cost < 12, "reading the selection costs \(cost)x a pass over the board")
    }
}
