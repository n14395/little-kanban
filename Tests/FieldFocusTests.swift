import Foundation
import Testing
@testable import Simple_Kanban

/// Fields that open with the keyboard already in them.
///
/// The reported bug: the column's "+" and the sidebar's New board both opened a
/// text field that did not take focus — a placeholder, no caret, and the first
/// thing typed going wherever the keyboard actually was. Every inline field in
/// this app is opened *by* something, so there is no second click to recover
/// with: an unfocused field is the whole interaction failing.
///
/// The cause is one line, repeated: `@FocusState` set from `onAppear` lands
/// before AppKit has finished installing the field and is dropped silently.
/// Measured against the built app, three of the app's fields had it — the two
/// reported and the toolbar's board rename — and two more were a keystroke away
/// from it. What made three of them possible is that each spelled the idiom out
/// for itself, so this asserts the opposite: that there is one spelling, in one
/// place.
///
/// **`scrollTo`'s problem, again.** Whether a field holds the keyboard is not a
/// value any test in this target can read — `@FocusState` belongs to a live view
/// hierarchy, and there is none here. So this reads the source, as
/// `BoardRevealTests` and `DragLiftTests` do. The behaviour was measured through
/// the accessibility API instead, reading the app's focused element after
/// pressing each control: `AXButton` before the fix on all three, `AXTextField`
/// after it.
@MainActor
@Suite struct FieldFocusTests {
    /// Every field in the app that opens focused, and the control that opens it.
    /// Named rather than counted so that a new one has to be added here, which
    /// is the moment somebody would otherwise write `onAppear` again.
    private static let fields = [
        "Shared/BoardTaskComposer.swift",   // a column's + , and the Inbox panel's
        "Shared/BoardSidebar.swift",        // New board, and renaming one
        "Shared/BoardToolbar.swift",        // the board's name in the title bar
        "Shared/BoardColumnView.swift",     // Add column, and the column editor
        "Shared/LabelEditor.swift",         // the new-label field in the popover
        "Mac/MenuBarQuickAdd.swift",        // ⌃⌘N, where the field is the window
        "IOS/PhoneNavDrawer.swift",         // the phone's rename sheet, when it was opened to rename
    ]

    private func sources() -> [SourceFile] { SourceTree.files() }

    /// The rule. `onAppear` is where all three of the broken ones set focus, and
    /// it is the one place a `@FocusState` may not be written.
    ///
    /// `@AccessibilityFocusState` is a *different* focus — it moves the
    /// VoiceOver cursor, has no run-loop problem, and `PhoneNavDrawer` sets one
    /// from `onAppear` on purpose. The two are told apart by how the property
    /// is declared rather than by an exception list, so this stays true of a
    /// file nobody has thought about yet.
    @Test func noFieldTakesTheKeyboardFromOnAppear() {
        guard SourceTree.isReachable else { return }
        for file in sources() {
            let source = file.source
            var searched = source.startIndex
            while let head = source.range(of: ".onAppear", range: searched..<source.endIndex) {
                searched = head.upperBound
                let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
                for assignment in body.matches(of: /(\w*[Ff]ocus\w*)\s*=\s*[^=]/) {
                    let name = String(assignment.1)
                    guard file.source.contains("@FocusState private var \(name)") else { continue }
                    Issue.record(
                        "\(file.path) takes the keyboard from onAppear, where it is dropped: \(body)"
                    )
                }
            }
        }
    }

    /// And each of them goes through the one modifier instead. Without this the
    /// rule above is satisfied by a field that never focuses at all, which is
    /// the same bug with the line deleted rather than fixed.
    @Test func everyFieldThatOpensFocusedGoesThroughTheOneModifier() {
        guard SourceTree.isReachable else { return }
        let found = sources().filter { $0.source.contains(".focusWhenReady(") }
        #expect(Set(found.map(\.path)) == Set(Self.fields),
                "the set of fields that open focused has changed: \(found.map(\.path).sorted())")
    }

    /// What the modifier has to do, which is the part that is easy to tidy away
    /// as a redundant hop. A bare `task` was measured and does **not** work: it
    /// starts in the turn the view was created in, which is the turn the field
    /// is not focusable in yet.
    @Test func theModifierYieldsBeforeItAsksForTheKeyboard() {
        guard SourceTree.isReachable else { return }
        guard let file = sources().first(where: { $0.path == "Shared/FocusWhenReady.swift" }) else {
            Issue.record("the focus modifier has moved file")
            return
        }
        let source = file.source
        #expect(source.contains("await Task.yield()"), "the modifier no longer waits for the field")
        guard let yield = source.range(of: "await Task.yield()"),
              let assignment = source.range(of: "focus.wrappedValue = ")
        else { return }
        #expect(yield.lowerBound < assignment.lowerBound,
                "the modifier asks for the keyboard before it yields, which is what onAppear did")

        // A sleep works too and is what this replaced. It is a duration that
        // happens to be long enough on one machine, so it must not come back.
        #expect(source.contains("Task.sleep") == false,
                "the modifier waits a fixed time rather than a turn")
    }
}
