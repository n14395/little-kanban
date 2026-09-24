// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import Foundation

/// What the user picks when they edit a widget.
///
/// **The pickers are filled from the digest, not from the app.** A widget is
/// configured in a process the app may not even be running behind — the system
/// runs the extension to draw the sheet — so `TaskIntentBridge`, which is how
/// the app's own Shortcuts entities are answered, has nothing to offer here.
/// The digest already carries every board, every column and every view by name,
/// which is exactly what a picker needs.
///
/// Each entity is a *reference*: an id and enough text to tell two of them
/// apart. Nothing about the contents is stored in the widget's configuration,
/// so a column renamed after the widget was placed draws under its new name at
/// the next refresh rather than under the name it had when it was picked.

// MARK: - Boards

struct WidgetBoardEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Board", comment: "What a board is called when configuring a widget")
    )
    static let defaultQuery = WidgetBoardQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetBoardQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetBoardEntity] {
        let wanted = Set(identifiers)
        return Self.all().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetBoardEntity] { Self.all() }

    /// What a freshly placed widget shows before anybody opens its editor. The
    /// first board is the app's own answer to "which board" everywhere else —
    /// it is what a launch lands on.
    func defaultResult() async -> WidgetBoardEntity? { Self.all().first }

    private static func all() -> [WidgetBoardEntity] {
        (WidgetDigestFile.read()?.boards ?? []).map { WidgetBoardEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Columns

/// A column, named with its board, because two boards can both have a Done and
/// the picker shows nothing else about them.
struct WidgetColumnEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Column", comment: "What a board column is called when configuring a widget")
    )
    static let defaultQuery = WidgetColumnQuery()

    var id: UUID
    var name: String
    var boardName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(boardName)")
    }
}

struct WidgetColumnQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetColumnEntity] {
        let wanted = Set(identifiers)
        return Self.all().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetColumnEntity] { Self.all() }

    /// The first board's *landing* column rather than its first, which on every
    /// board this app seeds is the same thing — and on a board whose first
    /// column is Done is the difference between a widget that starts on work
    /// waiting and one that starts on work finished.
    func defaultResult() async -> WidgetColumnEntity? { Self.all().first }

    private static func all() -> [WidgetColumnEntity] {
        (WidgetDigestFile.read()?.boards ?? []).flatMap { board in
            board.columns.map {
                WidgetColumnEntity(id: $0.id, name: $0.name, boardName: board.name)
            }
        }
    }
}

// MARK: - Saved views

struct WidgetViewEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("View", comment: "What a saved view is called when configuring a widget")
    )
    static let defaultQuery = WidgetViewQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetViewQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetViewEntity] {
        let wanted = Set(identifiers)
        return Self.all().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetViewEntity] { Self.all() }

    /// Today, when there is one. It is the view the app opens on the phone and
    /// the one this kind of widget is overwhelmingly placed for; somebody who
    /// deleted it gets whatever their first row is.
    func defaultResult() async -> WidgetViewEntity? {
        let views = WidgetDigestFile.read()?.views ?? []
        let start = views.first { $0.preset == WidgetList.todayPreset } ?? views.first
        return start.map { WidgetViewEntity(id: $0.id, name: $0.name) }
    }

    private static func all() -> [WidgetViewEntity] {
        (WidgetDigestFile.read()?.views ?? []).map { WidgetViewEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - The configurations themselves

/// The titles are the *same strings* the gallery shows — see each widget's
/// `configurationDisplayName`. A configuration screen headed "Board Overview"
/// under a widget called "Board overview" is two names for one thing, and a
/// translator handed both has no way to know they are.
struct BoardWidgetIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource(
        "Board overview", comment: "Widget name in the gallery: a board's columns and counts"
    )
    static let description = IntentDescription(
        LocalizedStringResource("Choose which board to show.",
                                comment: "What the board widget's editor asks for")
    )

    @Parameter(title: "Board")
    var board: WidgetBoardEntity?
}

struct ColumnWidgetIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource(
        "Column", comment: "What a board column is called when configuring a widget"
    )
    static let description = IntentDescription(
        LocalizedStringResource("Choose which column to show.",
                                comment: "What the column widget's editor asks for")
    )

    @Parameter(title: "Column")
    var column: WidgetColumnEntity?
}

struct SavedViewWidgetIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource(
        "Saved view", comment: "Widget name in the gallery: the cards in a saved view"
    )
    static let description = IntentDescription(
        LocalizedStringResource("Choose which saved view to show.",
                                comment: "What the saved view widget's editor asks for")
    )

    @Parameter(title: "View")
    var savedView: WidgetViewEntity?
}
