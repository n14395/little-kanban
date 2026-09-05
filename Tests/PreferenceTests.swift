import Foundation
import Testing
import UserNotifications
@testable import LittleKanban

/// The line between the board and the person looking at it.
///
/// `BoardSnapshot` is the *board*: what a second machine restoring from an
/// export would need. A preference — which accent, when notifications fire,
/// whether the inspector is open — belongs to the sitting, not to the work, and
/// putting one in the snapshot has two costs the compiler cannot see. It is a
/// schema change, so it needs a version bump and a migration or it destroys
/// older files (C7); and it travels, so an import silently reaches across and
/// changes the importing machine's settings.
@Suite struct PreferenceTests {
    private func encoded(_ snapshot: BoardSnapshot) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let object = try JSONSerialization.jsonObject(with: try encoder.encode(snapshot))
        return try #require(object as? [String: Any])
    }

    /// Every key the board document is allowed to carry, written out.
    ///
    /// This is the assertion a preference has to get past. Adding a field to
    /// `BoardSnapshot` fails here, which is the point: the failure is the
    /// prompt to decide whether the thing being added is board data — and
    /// therefore needs `currentVersion` bumped and a migration step — or a
    /// preference, which belongs in `@AppStorage` and must not be here at all.
    static let boardKeys: Set<String> = [
        "version", "tasks", "boards", "labels", "nextSerial", "themes", "activeBoardID",
        "trash", "palette", "views",
    ]

    @Test func theBoardDocumentCarriesExactlyTheKeysItIsAllowedTo() throws {
        let snapshot = BoardSnapshot(
            tasks: TestBoard.tasks, boards: TestBoard.boards, labels: LabelDef.seed,
            nextSerial: 137, activeBoardID: TestBoard.support.id
        )
        let keys = Set(try encoded(snapshot).keys)
        #expect(keys == Self.boardKeys,
                "unexpected: \(keys.subtracting(Self.boardKeys).sorted()); missing: \(Self.boardKeys.subtracting(keys).sorted())")
    }

    /// The same claim one level down, because a preference is just as damaging
    /// smuggled onto a task or a board as it is at the top.
    @Test func aTaskAndABoardCarryOnlyTheirOwnFields() throws {
        let snapshot = BoardSnapshot(
            tasks: TestBoard.tasks, boards: TestBoard.boards, labels: LabelDef.seed,
            nextSerial: 137, activeBoardID: TestBoard.support.id
        )
        let object = try encoded(snapshot)
        let taskKeys: Set<String> = [
            "id", "code", "boardID", "columnID", "title", "note", "labelKeys", "due",
            "priority", "subtasks", "activity", "createdAt", "updatedAt", "inboxCompletedAt", "archivedAt",
        ]
        let tasks = try #require(object["tasks"] as? [[String: Any]])
        let everyTaskKey = Set(tasks.flatMap(\.keys))
        #expect(everyTaskKey.isSubset(of: taskKeys),
                "unexpected task keys: \(everyTaskKey.subtracting(taskKeys).sorted())")

        let boardKeys: Set<String> = ["id", "name", "symbol", "createdAt", "columns", "codePrefix"]
        let boards = try #require(object["boards"] as? [[String: Any]])
        let everyBoardKey = Set(boards.flatMap(\.keys))
        #expect(everyBoardKey.isSubset(of: boardKeys),
                "unexpected board keys: \(everyBoardKey.subtracting(boardKeys).sorted())")
    }

    // MARK: Every preference the settings surface offers

    /// The two preferences that are written to `UserDefaults.standard` rather
    /// than to an injected suite, kept and put back.
    ///
    /// `xcodebuild test` launches the app as the test host under its real
    /// bundle identifier, so `.standard` here is the developer's own
    /// preferences — the same hazard `BoardFile.default` guards against. A suite
    /// that left these behind would change the app's behaviour on the machine
    /// it ran on.
    private struct BorrowedDefaults {
        private let keys: [String]
        private let previous: [String: Any]

        init(_ keys: [String]) {
            self.keys = keys
            previous = keys.reduce(into: [:]) { store, key in
                if let value = UserDefaults.standard.object(forKey: key) { store[key] = value }
            }
        }

        func giveBack() {
            for key in keys {
                if let value = previous[key] {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }

    /// Item 6.1's claim, asked of the file: set every preference the settings
    /// surface offers and the board document does not move a byte.
    ///
    /// It is not a style question. A preference in `BoardSnapshot` is a schema
    /// change that needs a version bump and a migration or it destroys older
    /// files, and it travels — an import would reach across and change the
    /// importing machine's appearance, its reminder time and the order its
    /// cards are drawn in.
    @MainActor
    @Test func settingEveryPreferenceLeavesTheBoardDocumentUntouched() throws {
        let borrowed = BorrowedDefaults([
            AppAppearance.storageKey, BoardStore.sortOrderKey,
            Preferences.completionSoundKey, CompletionSound.storageKey,
            Preferences.subtaskSoundKey, CompletionSound.subtaskStorageKey,
        ])
        defer { borrowed.giveBack() }

        let temp = TempBoard()
        let store = TestBoard.store(boards: TestBoard.boards, file: temp.file)
        store.saveNow()
        let before = try temp.bytes()

        // Appearance — the spec's `state.dark`, back as a preference.
        UserDefaults.standard.set(AppAppearance.dark.rawValue, forKey: AppAppearance.storageKey)
        // Board — how a column orders its cards.
        store.sortOrder = .dueDate
        // Completion feedback — the two switches and the two chosen chimes.
        UserDefaults.standard.set(false, forKey: Preferences.completionSoundKey)
        UserDefaults.standard.set(CompletionSound.glassTriad.rawValue, forKey: CompletionSound.storageKey)
        UserDefaults.standard.set(false, forKey: Preferences.subtaskSoundKey)
        UserDefaults.standard.set(CompletionSound.bowl.rawValue, forKey: CompletionSound.subtaskStorageKey)
        // Notifications — on or off, and the time of day.
        let suite = try #require(UserDefaults(suiteName: "LittleKanbanTests-\(UUID().uuidString)"))
        let scheduler = NotificationScheduler(center: nil, defaults: suite)
        scheduler.isEnabled = false
        scheduler.reminderHour = 6
        scheduler.reminderMinute = 15

        store.saveNow()
        #expect(try temp.bytes() == before, "a preference reached the board file")

        // …and the same after a relaunch reads it back.
        let reread = try #require(temp.file.load().snapshot)
        #expect(reread.tasks == store.tasks)
        #expect(reread.boards == store.boards)
        #expect(reread.labels == store.labels)
        #expect(reread.themes == store.themes)
        #expect(reread.activeBoardID == store.activeBoardID)
        #expect(Set(try encoded(reread).keys) == Self.boardKeys)

        let text = try temp.text()
        for key in [AppAppearance.storageKey, BoardStore.sortOrderKey,
                    "LittleKanbanRemindersEnabled", "LittleKanbanReminderHour",
                    "LittleKanbanReminderMinute"] {
            #expect(!text.contains(key), "\(key) is written into the board file")
        }
        #expect(!text.contains("dueDate"), "the sort order reached the board file")
    }

    /// The one setting on that screen that *is* board data, so the probe above
    /// cannot pass by the store having quietly stopped saving.
    ///
    /// The accent was in `BoardSnapshot` before there was a settings surface to
    /// move it out of, and moving it now is a schema change for no gain — see
    /// **Settings** in the README.
    @MainActor
    @Test func theThemesAreTheOnePreferenceThatIsBoardData() throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        store.saveNow()
        let before = try temp.bytes()

        store.selectTheme(TestBoard.otherDarkTheme)
        store.saveNow()
        #expect(try temp.bytes() != before)
        #expect(try temp.snapshot().themes.darkID == TestBoard.otherDarkTheme.id)
    }

    /// A store with no file is a preview or a test, and neither may leave a
    /// preference behind on the machine it ran on.
    @MainActor
    @Test func anInMemoryStoreWritesNoPreferences() {
        let borrowed = BorrowedDefaults([BoardStore.sortOrderKey])
        defer { borrowed.giveBack() }
        UserDefaults.standard.removeObject(forKey: BoardStore.sortOrderKey)

        let store = TestBoard.store()
        store.sortOrder = .priority
        #expect(store.sortOrder == .priority)
        #expect(UserDefaults.standard.object(forKey: BoardStore.sortOrderKey) == nil)
    }

    /// An imported board carries the exporting machine's themes and active
    /// board in its document, and neither is the file's to change — importing
    /// somebody's board must not repaint the app.
    @MainActor
    @Test func anImportedFileCannotReachAcrossAndChangeThisMachine() {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let themes = store.themes
        let active = store.activeBoardID
        let order = store.sortOrder

        store.importBoard(ForeignBoard.snapshot(includingCollision: true))

        #expect(store.themes == themes)
        #expect(store.activeBoardID == active)
        #expect(store.sortOrder == order)
    }

    /// Session state has never been in the snapshot, and the settings surface
    /// is the first thing with a plausible reason to put some of it there.
    ///
    /// Driven through the store rather than asserted about the struct: what
    /// matters is that moving around the app leaves the *file* alone, and the
    /// snapshot is assembled in `BoardStore` where a new field would be wired
    /// in.
    @MainActor
    @Test func movingAroundTheAppChangesNothingInTheFile() throws {
        let temp = TempBoard()
        let store = TestBoard.store(boards: TestBoard.boards, file: temp.file)
        store.saveNow()
        let before = try temp.bytes()

        store.isInspectorOpen.toggle()
        store.isNavDrawerOpen.toggle()
        store.isShowingShortcuts.toggle()
        store.isShowingTrash.toggle()
        store.tab = .search
        store.showInbox()
        store.query = "palette"
        store.mobileColumnID = BoardColumn.backlog.id
        store.select(TestBoard.offline)
        store.draggingID = TestBoard.cafe
        store.dropTargetColumnID = BoardColumn.done.id
        store.draft = "half-typed"
        store.beginAdding(in: BoardColumn.upNext.id)

        store.saveNow()
        #expect(try temp.bytes() == before)
    }

    /// …and the one piece of surface state that *is* saved, so the test above
    /// cannot pass by the store having stopped saving anything.
    @MainActor
    @Test func theActiveBoardIsSavedWhereTheSurfaceIsNot() throws {
        let temp = TempBoard()
        let store = TestBoard.store(boards: TestBoard.boards, file: temp.file)
        store.saveNow()
        let before = try temp.bytes()

        store.selectBoard(TestBoard.support.id)
        store.saveNow()
        #expect(try temp.bytes() != before)
        #expect(try temp.snapshot().activeBoardID == TestBoard.support.id)
    }
}
