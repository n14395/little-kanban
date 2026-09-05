import Foundation
import Testing
@testable import Cardstock

/// A folder for captures, thrown away with the test — `TempBoard` for the App
/// Group's side of the fence.
final class TempCaptures: Sendable {
    let directory: URL

    init() {
        directory = URL.temporaryDirectory.appending(path: "CardstockCaptures/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).sorted()
    }

    func put(_ text: String, named name: String) throws {
        try Data(text.utf8).write(to: directory.appending(path: name))
    }
}

/// What a share sheet's payload becomes, before any of it touches a disk.
///
/// The whole reason `CaptureDraft.from(text:url:)` is a free function of two
/// optionals: no test in this suite can present a share sheet, drive an
/// `NSItemProvider` or run an app extension, so the rules have to live
/// somewhere that can be asked directly.
@Suite struct CaptureDraftTests {
    private let when = Date(timeIntervalSinceReferenceDate: 777_000_000)

    @Test func aSharedPageBecomesItsTitleWithTheLinkInTheNote() {
        let draft = CaptureDraft.from(
            text: "Swift Concurrency, explained",
            url: URL(string: "https://example.com/swift/concurrency"),
            now: when
        )
        #expect(draft.title == "Swift Concurrency, explained")
        #expect(draft.note == "https://example.com/swift/concurrency")
        #expect(draft.createdAt == when)
    }

    /// Safari sends the page name as text and the address as an attachment, but
    /// plenty of apps share a bare link. It has to name itself in a column.
    @Test func aBareLinkNamesItselfByItsHost() {
        let draft = CaptureDraft.from(text: nil, url: URL(string: "https://www.example.com/a/b?c=d"), now: when)
        #expect(draft.title == "example.com", "www. is four characters of nothing")
        #expect(draft.note == "https://www.example.com/a/b?c=d", "the whole address is still kept")
    }

    @Test func aLinkWithNoHostIsNamedByTheWholeThing() {
        let draft = CaptureDraft.from(text: nil, url: URL(string: "mailto:someone@example.com"), now: when)
        #expect(draft.title == "mailto:someone@example.com")
    }

    /// A shared selection is usually several lines. The first is the card; the
    /// rest is the note, in the order it was written.
    @Test func theFirstLineIsTheTitleAndTheRestIsTheNote() {
        let draft = CaptureDraft.from(
            text: "Refactor the parser\n\nIt allocates twice per token.\nSee the profile.",
            url: nil, now: when
        )
        #expect(draft.title == "Refactor the parser")
        #expect(draft.note == "It allocates twice per token.\n\nSee the profile.")
    }

    /// **Nothing is dropped — it moves.** Sharing a paragraph should give a card
    /// you can read in a column, and achieving that by throwing the paragraph
    /// away would be a strange trade.
    @Test func aTitleTooLongToReadIsCutAndKeptWholeInTheNote() {
        let long = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        let draft = CaptureDraft.from(text: long, url: nil, now: when)

        #expect(draft.title.count <= CaptureDraft.titleLimit + 1, "the ellipsis is the only thing over the limit")
        #expect(draft.title.hasSuffix("…"))
        #expect(draft.title.hasPrefix("word word"))
        #expect(draft.note.hasPrefix(long), "the whole of the original line has to be in the note")
    }

    @Test func aShareCarryingNothingMakesAnEmptyDraftForTheCallerToRefuse() {
        let draft = CaptureDraft.from(text: nil, url: nil, now: when)
        #expect(draft.title.isEmpty)
        #expect(draft.note.isEmpty)
    }

    @Test func blankLinesAndPaddingAreNotAtitle() {
        let draft = CaptureDraft.from(text: "\n   \n  Real title  \n", url: nil, now: when)
        #expect(draft.title == "Real title")
    }
}

/// The folder itself: what the extension writes and what the app finds.
@MainActor
@Suite struct CaptureInboxTests {
    private func capture(_ title: String, at seconds: Int) -> PendingCapture {
        PendingCapture(title: title, note: "", createdAt: Date(timeIntervalSinceReferenceDate: Double(seconds)))
    }

    @Test func aCaptureIsWrittenAndReadBackWhole() throws {
        let temp = TempCaptures()
        try CaptureInbox.using(temp.directory) {
            let written = PendingCapture(title: "Read this", note: "https://example.com", createdAt: .now)
            try CaptureInbox.write(written)

            let (found, unreadable) = CaptureInbox.pending()
            #expect(unreadable.isEmpty)
            #expect(found.count == 1)
            #expect(found.first?.id == written.id)
            #expect(found.first?.title == "Read this")
            #expect(found.first?.note == "https://example.com")
        }
    }

    /// One file each, so two share sheets in quick succession are two captures
    /// rather than one overwriting the other.
    @Test func everyCaptureGetsAFileOfItsOwn() throws {
        let temp = TempCaptures()
        try CaptureInbox.using(temp.directory) {
            try CaptureInbox.write(capture("First", at: 10))
            try CaptureInbox.write(capture("Second", at: 20))
            try CaptureInbox.write(capture("Third", at: 30))

            #expect(temp.names().count == 3)
            #expect(CaptureInbox.pending().captures.count == 3)
        }
    }

    /// The order they were shared in, not whatever the directory enumerator
    /// happens to hand back — which has no ordering contract at all.
    @Test func capturesComeBackOldestFirst() throws {
        let temp = TempCaptures()
        try CaptureInbox.using(temp.directory) {
            try CaptureInbox.write(capture("Third", at: 30))
            try CaptureInbox.write(capture("First", at: 10))
            try CaptureInbox.write(capture("Second", at: 20))

            #expect(CaptureInbox.pending().captures.map(\.title) == ["First", "Second", "Third"])
        }
    }

    @Test func removingOneLeavesTheRest() throws {
        let temp = TempCaptures()
        try CaptureInbox.using(temp.directory) {
            let first = capture("First", at: 10)
            try CaptureInbox.write(first)
            try CaptureInbox.write(capture("Second", at: 20))

            CaptureInbox.remove(first.id)
            #expect(CaptureInbox.pending().captures.map(\.title) == ["Second"])
        }
    }

    /// **A capture is not a cache.** The widgets' digest is refused and
    /// forgotten when it will not decode, because the app rewrites it within
    /// half a second. This is the only copy of something somebody typed, so it
    /// is set aside — still on disk, and no longer offered.
    @Test func anUnreadableCaptureIsSetAsideRatherThanDeletedOrRetried() throws {
        let temp = TempCaptures()
        try CaptureInbox.using(temp.directory) {
            try temp.put("{ not json", named: "\(UUID().uuidString).json")
            try CaptureInbox.write(capture("Good one", at: 10))

            let (found, unreadable) = CaptureInbox.pending()
            #expect(found.map(\.title) == ["Good one"], "a broken file must not stop the readable ones")
            #expect(unreadable.count == 1)

            for file in unreadable { CaptureInbox.reject(file) }

            #expect(temp.names().contains { $0.hasSuffix(".rejected") }, "the broken capture was deleted")
            #expect(CaptureInbox.pending().unreadable.isEmpty, "a rejected capture is still being offered")
        }
    }

    @Test func anEmptyFolderIsNotAFailure() {
        let temp = TempCaptures()
        CaptureInbox.using(temp.directory) {
            let (found, unreadable) = CaptureInbox.pending()
            #expect(found.isEmpty)
            #expect(unreadable.isEmpty)
        }
    }
}

/// The app's side: draining the folder into the Inbox.
@MainActor
@Suite struct AdoptingCapturesTests {
    private func store() -> BoardStore {
        TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
    }

    @Test func sharedItemsBecomeInboxCardsInTheOrderTheyWereShared() throws {
        let temp = TempCaptures()
        let store = store()
        let before = store.inboxTasks.count

        try CaptureInbox.using(temp.directory) {
            try CaptureInbox.write(PendingCapture(
                title: "Second", note: "", createdAt: Date(timeIntervalSinceReferenceDate: 20)
            ))
            try CaptureInbox.write(PendingCapture(
                title: "First", note: "https://example.com", createdAt: Date(timeIntervalSinceReferenceDate: 10)
            ))

            #expect(store.adoptPendingCaptures() == 2)
        }

        let made = store.tasks.filter { $0.title == "First" || $0.title == "Second" }
        #expect(made.count == 2)
        let allInInbox = made.allSatisfy(\.isUnfiled)
        #expect(allInInbox, "a shared item must land in the Inbox, not on a board")
        #expect(store.inboxTasks.count == before + 2)
        // The note came across whole.
        #expect(made.first { $0.title == "First" }?.note == "https://example.com")
        // Captured, not created: this arrived through the share sheet, which is
        // the same errand the menu bar's quick add is on. Hoisted out of
        // `#expect`, which reads `allSatisfy` as a rethrowing call it then has
        // to handle.
        let allCaptured = made.allSatisfy { task in
            task.activity.contains { entry in
                if case .captured = entry.kind { return true }
                return false
            }
        }
        #expect(allCaptured, "a shared item was logged as created rather than captured")
    }

    /// The folder is the queue, so a drained capture has to leave it — twice
    /// through the same folder must not produce the card twice.
    @Test func drainingTakesTheFilesWithIt() throws {
        let temp = TempCaptures()
        let store = store()

        try CaptureInbox.using(temp.directory) {
            try CaptureInbox.write(PendingCapture(title: "Once", note: "", createdAt: .now))
            #expect(store.adoptPendingCaptures() == 1)

            #expect(temp.names().isEmpty, "a drained capture was left in the folder")
            #expect(store.adoptPendingCaptures() == 0)
        }
        #expect(store.tasks.filter { $0.title == "Once" }.count == 1)
    }

    /// N shares cost one ⌘Z, the way a paste of N lines does.
    @Test func theWholeDrainIsOneUndoStep() throws {
        let temp = TempCaptures()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let store = store()
        store.undoManager = undo
        let before = store.tasks.count

        try CaptureInbox.using(temp.directory) {
            for index in 0..<3 {
                try CaptureInbox.write(PendingCapture(
                    title: "Shared \(index)", note: "",
                    createdAt: Date(timeIntervalSinceReferenceDate: Double(index))
                ))
            }
            step(undo) { _ = store.adoptPendingCaptures() }
        }

        #expect(store.tasks.count == before + 3)
        #expect(undo.undoActionName != "", "the drain registered no undo step")
        undo.undo()
        #expect(store.tasks.count == before, "one ⌘Z did not take all three back")
    }

    /// Safe to call at any moment, which is what lets it sit on `.onAppear` and
    /// on every `.active` without a guard at the call site.
    @Test func drainingNothingChangesNothing() {
        let temp = TempCaptures()
        let store = store()
        let before = store.tasks.count

        CaptureInbox.using(temp.directory) {
            #expect(store.adoptPendingCaptures() == 0)
        }
        #expect(store.tasks.count == before)
        #expect(store.announcement == nil, "a drain that found nothing announced something")
    }

    @Test func aBrokenCaptureIsSetAsideAndTheGoodOnesStillArrive() throws {
        let temp = TempCaptures()
        let store = store()

        try CaptureInbox.using(temp.directory) {
            try temp.put("nonsense", named: "\(UUID().uuidString).json")
            try CaptureInbox.write(PendingCapture(title: "Fine", note: "", createdAt: .now))

            #expect(store.adoptPendingCaptures() == 1)
            #expect(temp.names() == temp.names().filter { $0.hasSuffix(".rejected") },
                    "the folder should hold nothing but the rejected file")
        }
        #expect(store.tasks.contains { $0.title == "Fine" })
    }
}
