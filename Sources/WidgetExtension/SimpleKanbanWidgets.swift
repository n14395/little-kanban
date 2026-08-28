import SwiftUI
import WidgetKit

/// The four widgets, and the whole of the extension's entry point.
///
/// Four kinds rather than one configurable "Simple Kanban" widget, because the
/// gallery is where somebody decides what to put on their screen and a single
/// row called "Simple Kanban" tells them nothing about the four things it could
/// be. The identifiers are in ``WidgetShare/Kind`` — the system stores them
/// against every widget a user has placed, so they are not free to change.
@main
struct SimpleKanbanWidgets: WidgetBundle {
    var body: some Widget {
        InboxWidget()
        SavedViewWidget()
        ColumnWidget()
        BoardOverviewWidget()
    }
}
