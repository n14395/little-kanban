import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Cardstock

/// The drag payloads. Their `plainText` is not a rendering detail: it is what a
/// card dropped into a text editor leaves behind, and what Phase E's ⌘C will put
/// on the pasteboard, so its exact shape belongs in a test.
@Suite struct TransferTests {

    // MARK: The plain-text representation

    @Test func aDraggedCardReadsAsItsCodeAndTitle() {
        #expect(TaskTransfer(TestBoard.tasks[1]).plainText == "NW-121 Drag and drop between columns")
    }

    @Test func aCardDraggedBeforeItWasNamedStillSaysSomething() {
        var untitled = TestBoard.tasks[2]
        untitled.title = "   "
        // `displayTitle`, not `title`: a line reading "NW-122 " is not one.
        #expect(TaskTransfer(untitled).plainText == "NW-122 \(untitled.displayTitle)")
    }

    @Test func aDraggedChecklistRowReadsAsItsText() {
        let row = TestBoard.tasks[1].subtasks[0]
        #expect(SubtaskTransfer(row, on: TestBoard.dragDrop).text == "Lift and shadow states")
    }

    @Test func aDraggedColumnReadsAsItsName() {
        #expect(ColumnTransfer(BoardColumn.inProgress, on: TestBoard.boards[0].id).name == "In Progress")
    }

    @Test func aDraggedLabelReadsAsItsName() {
        #expect(LabelTransfer(LabelDef.seed[0]).name == LabelDef.seed[0].name)
    }

    // MARK: The codable representation

    @Test func aCardPayloadSurvivesAJSONRoundTrip() throws {
        let original = TaskTransfer(TestBoard.tasks[1])
        let decoded = try JSONDecoder().decode(TaskTransfer.self, from: JSONEncoder().encode(original))
        #expect(decoded.id == TestBoard.dragDrop)
        #expect(decoded.code == "NW-121")
        #expect(decoded.title == original.title)
    }

    @Test func aChecklistRowPayloadKeepsBothIDs() throws {
        // Both, because a row dragged out of the inspector must not be able to
        // land in the sheet's checklist for a different task.
        let original = SubtaskTransfer(TestBoard.tasks[1].subtasks[0], on: TestBoard.dragDrop)
        let decoded = try JSONDecoder().decode(SubtaskTransfer.self, from: JSONEncoder().encode(original))
        #expect(decoded.taskID == TestBoard.dragDrop)
        #expect(decoded.subtaskID == TestBoard.lift)
        #expect(decoded.text == original.text)
    }

    @Test func aColumnPayloadKeepsItsBoard() throws {
        // Both, because `moveColumn` is defined over the active board: a column
        // dropped from a second macOS window showing another one would name an
        // index in a list it is not in.
        let board = TestBoard.support
        let original = ColumnTransfer(TestBoard.queue, on: board.id)
        let decoded = try JSONDecoder().decode(ColumnTransfer.self, from: JSONEncoder().encode(original))
        #expect(decoded.boardID == board.id)
        #expect(decoded.columnID == TestBoard.queue.id)
        #expect(decoded.name == "Queue")
    }

    @Test func aLabelPayloadKeepsItsKey() throws {
        // The key, because it is the identity every task stores — a payload
        // reduced to its display name could not find its own row after a rename.
        let original = LabelTransfer(LabelDef.seed[0])
        let decoded = try JSONDecoder().decode(LabelTransfer.self, from: JSONEncoder().encode(original))
        #expect(decoded.key == LabelDef.seed[0].key)
        #expect(decoded.name == LabelDef.seed[0].name)
    }

    // MARK: The exported types

    @Test func theExportedTypesMatchWhatTheBundleDeclares() throws {
        // Read the host bundle's declarations rather than asking `UTType` what
        // it conforms to. An exported identifier resolves through
        // LaunchServices, which remembers every build of this app that has ever
        // run on the machine — it answers `conforms(to: .data)` with yes long
        // after the declaration went away, so it cannot tell the code and
        // `project.yml` apart. The plist in the bundle under test can.
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
                as? [[String: Any]],
            "the test host declares no exported types at all"
        )
        let conformances = Dictionary(
            uniqueKeysWithValues: declared.compactMap { entry -> (String, [String])? in
                guard let id = entry["UTTypeIdentifier"] as? String else { return nil }
                return (id, entry["UTTypeConformsTo"] as? [String] ?? [])
            }
        )

        for type in [UTType.simpleKanbanTask, .simpleKanbanSubtask, .simpleKanbanColumn,
                     .simpleKanbanLabel] {
            let plist = try #require(
                conformances[type.identifier],
                "\(type.identifier) is used in code but not declared in project.yml"
            )
            // Both halves say `public.data`; a drag payload whose type conforms
            // to nothing is not offered to anything that accepts data.
            #expect(plist.contains(UTType.data.identifier))
            #expect(type.conforms(to: .data))
        }
    }
}
