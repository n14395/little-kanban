import XCTest

/// Temporary diagnostic — deleted once `GroundDropFootTests` is understood.
final class ZGroundDropProbe: XCTestCase {
    private func cards(
        in app: XCUIApplication, trailingOf divide: CGFloat? = nil, leadingOf: CGFloat? = nil
    ) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex
            .filter { element in
                let frame = element.frame
                guard frame.width > 100, app.frame.contains(frame) else { return false }
                let label = element.label
                guard !label.hasPrefix("Mark as"), !label.contains("Add task to") else { return false }
                if let divide, frame.midX < divide { return false }
                if let leadingOf, frame.midX > leadingOf { return false }
                return true
            }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    func testProbe() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "phone only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES", "-SimpleKanbanTab", "board"]
        app.launch()
        var log = "window=\(app.frame)\n"
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20), "the app never came up")

        func dashedRow() -> XCUIElement? {
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "Add task to"))
                .allElementsBoundByIndex
                .first { app.frame.contains($0.frame) }
        }
        var found = dashedRow()
        for _ in 0..<4 where found == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.4)))
            found = dashedRow()
        }
        guard let dashed = found else { return XCTFail("PROBE no dashed row.\n\(log)") }
        let row = dashed.frame
        log += "dashed=\(dashed.label) frame=\(row)\n"

        let landing = cards(in: app, leadingOf: row.maxX)
        let beside = cards(in: app, trailingOf: row.maxX)
        log += "landing=\(landing.map { "\($0.label.prefix(20))@\($0.frame)" })\n"
        log += "beside=\(beside.map { "\($0.label.prefix(20))@\($0.frame)" })\n"
        guard let foot = landing.last?.frame else { return XCTFail("PROBE no landing cards.\n\(log)") }
        guard let moving = beside.min(by: {
            ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY)
        }) else { return XCTFail("PROBE no beside card.\n\(log)") }
        let carried = moving.label
        log += "foot=\(foot)\ncarried=\(carried.prefix(40)) from=\(moving.frame)\n"

        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row.midX, dy: row.midY))
        func card(_ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        func drag() {
            card(carried)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.55, thenDragTo: target,
                       withVelocity: .slow, thenHoldForDuration: 0.6)
        }
        drag()
        Thread.sleep(forTimeInterval: 1.5)
        log += "afterFirstDrag=\(card(carried).frame)\n"
        if card(carried).frame.midX > row.maxX {
            drag()
            Thread.sleep(forTimeInterval: 1.5)
            log += "afterRetry=\(card(carried).frame)\n"
        }
        let moved = card(carried).frame
        log += "final=\(moved) wantMidXNear=\(foot.midX) wantMinY>\(foot.minY)\n"
        log += "dMidX=\(abs(moved.midX - foot.midX)) minYok=\(moved.minY > foot.minY)\n"
        XCTFail("PROBE\n\(log)")
    }
}
