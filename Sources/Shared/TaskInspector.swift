import SwiftUI

/// The detail panel. Same content as the iOS sheet, different container.
///
/// Every field here writes straight through to the store, so an edit shows on
/// the board card as it is typed. Activity is logged once per editing session
/// rather than once per keystroke — see `BoardStore.beginEditing`.
struct TaskInspector: View {
    /// The panel at a pointer and the panel under a finger. The controls inside
    /// it already carry their own two presets, so most of this is naming which
    /// of the two each one gets; the rest is the panel's own furniture.
    struct Metrics {
        /// `nil` where the container decides — a `NavigationSplitView`
        /// inspector column sizes itself.
        var width: CGFloat?
        var horizontalPadding: CGFloat
        var sectionSpacing: CGFloat
        var titleSize: CGFloat
        var noteSize: CGFloat
        var fieldNameSize: CGFloat
        var fieldNameWidth: CGFloat
        /// The square each of the header's three controls claims — the tick,
        /// the trash and the close ✕ alike. See ``TaskInspector/header``.
        var headerButton: CGFloat
        var headerButtonRadius: CGFloat
        /// The symbol inside it. One size for all three, so the row reads as a
        /// set rather than as three controls that happen to sit together.
        var headerGlyph: CGFloat
        /// What the two text fields claim — see ``FieldHitArea``.
        var fieldHit: CGFloat
        /// The tick, which is one of the three controls in the header. Its own
        /// preset rather than the card's, because what it has to match here is
        /// the square its neighbours claim — see ``TaskInspector/header``.
        var tick: CompletionToggle.Metrics
        var destination: BoardDestinationMenu.Metrics
        var moveTo: MoveToPicker.Metrics
        var due: DueDateField.Metrics
        var priority: PriorityPicker.Metrics
        var labels: LabelEditor.Metrics
        var checklist: ChecklistView.Metrics
        var activity: ActivityFeed.Metrics

        static let desk = Metrics(
            width: 336, horizontalPadding: 18, sectionSpacing: 18, titleSize: 26, noteSize: 13,
            fieldNameSize: 12.5, fieldNameWidth: 84, headerButton: 32, headerButtonRadius: 9,
            headerGlyph: 13,
            fieldHit: 0, tick: .deskHeader, destination: .desk, moveTo: .desk, due: .desk,
            priority: .desk, labels: .desk, checklist: .desk, activity: .desk
        )
        static let pad = Metrics(
            width: nil, horizontalPadding: 20, sectionSpacing: 20, titleSize: 29, noteSize: 14.5,
            fieldNameSize: 14, fieldNameWidth: 92, headerButton: 48, headerButtonRadius: 14,
            headerGlyph: 17,
            fieldHit: 44, tick: .sheetHeader, destination: .sheet, moveTo: .sheet, due: .sheet,
            priority: .sheet, labels: .sheet, checklist: .sheet, activity: .sheet
        )
    }

    /// Where the panel is being shown, which decides two things: what its ✕
    /// does, and whether it rules a seam down its leading edge.
    ///
    /// `.column` is the detail pane. It has the board to its left, so it rules
    /// the line the design draws between the two, and closing it means putting
    /// the pane away. `.popover` carries its own way out — closing the *pane*
    /// from inside a popover would put away something the user cannot see and
    /// leave the popover standing — and rules nothing, having nothing beside it.
    enum Container {
        case column
        case popover(dismiss: () -> Void)
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    var metrics: Metrics = .desk
    var container: Container = .column

    /// The panel is a 336pt box around type that grows, so it grows too — see
    /// ``ChromeScale``. Capped harder than the board's columns are: the panel
    /// takes its width off the board rather than off a scroller, and at AX5 an
    /// uncapped 336 is half an iPad.
    private var chrome = ChromeScale()

    /// How far the panel's width may grow with the reader's text size. Named
    /// so both roots grow their own empty panel by exactly as much — a panel
    /// that changed width when a card was picked would step the board.
    static let widthCap: CGFloat = 1.35

    @FocusState private var focusedField: TaskField?
    /// Which task the focused field belongs to. Selecting another card swaps
    /// `task` underneath a live focus, so the snapshot is closed against the
    /// task that was actually being edited.
    @State private var focusOwnerID: TaskItem.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    titleField
                    noteField
                    status
                    attributes
                    checklist
                    activity
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, metrics.horizontalPadding)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: chrome.scaling(metrics.width, cap: Self.widthCap))
        .background(palette.panel)
        .hairline(.leading, color: isColumn ? palette.ink(0.08) : .clear)
        .transition(.opacity)
        // What Handoff carries to the other device, and what Spotlight offers
        // back. The inspector is the macOS answer to "the task that is open".
        .taskUserActivity(task)
        .onChange(of: focusedField) { previous, current in
            if let previous, let owner = focusOwnerID {
                store.endEditing(previous, on: owner, scope: .desk)
            }
            focusOwnerID = current == nil ? nil : task.id
            if let current { store.beginEditing(current, on: task.id, scope: .desk) }
        }
        .onChange(of: task.id) { previousID, _ in
            if let field = focusedField, let owner = focusOwnerID, owner == previousID {
                store.endEditing(field, on: owner, scope: .desk)
            }
            focusOwnerID = nil
            focusedField = nil
        }
        // Closing the panel mid-edit takes the field out of the hierarchy;
        // whether SwiftUI clears `focusedField` first is not guaranteed, and a
        // session left open never logs the rename and never restores a title
        // emptied to whitespace. Closed against the task that was being edited,
        // which may no longer be `task`.
        .onDisappear {
            if let field = focusedField, let owner = focusOwnerID {
                store.endEditing(field, on: owner, scope: .desk)
            }
            focusOwnerID = nil
        }
        .onAppear { claimPendingFocus() }
        .onChange(of: store.pendingTitleFocusID) { _, _ in claimPendingFocus() }
    }

    private var isColumn: Bool {
        if case .column = container { true } else { false }
    }

    /// The header's ✕. See ``Container``.
    private func close() {
        switch container {
        case .column: store.isInspectorOpen = false
        case .popover(let dismiss): dismiss()
        }
    }

    /// A task created without a title opens with the title field ready.
    private func claimPendingFocus() {
        guard store.pendingTitleFocusID == task.id else { return }
        store.pendingTitleFocusID = nil
        focusedField = .title
    }

    /// The panel's own row: what finishes the card, what throws it away, and
    /// what closes the panel — in that order, left to right, so the two that
    /// end the card's life on this surface sit furthest from the one that only
    /// ends the *view* of it.
    ///
    /// **All three claim the same square**, `headerButton`, and carry the same
    /// `headerGlyph` inside it. The size is one number rather than three that
    /// agree, because three that agree is a thing an edit quietly breaks — and
    /// what is being claimed here is that they read as one set of controls, not
    /// that they were each given a plausible size on their own.
    ///
    /// **The tick moved here from beside the title.** It sat at the trailing
    /// edge of the title row, where it was the only control in a column of
    /// *fields* — a state verb standing in the middle of an editing surface,
    /// sized against a 26pt serif line rather than against anything it shared a
    /// row with. In the header it stands with the panel's other two verbs, at
    /// their size.
    ///
    /// **The task code is not in it.** `NW-118` sat at the leading edge of every
    /// editor on both platforms, and it is the one thing on this panel that
    /// nothing can do anything with: it cannot be edited, it names nothing the
    /// user chose, and it is already carried by every route that needs it — the
    /// `simplekanban://` link Copy Link puts on the pasteboard, the due-date
    /// reminder, the Markdown export, Spotlight, and the search field, which
    /// still finds a card by its code. What it cost was the first line of the
    /// panel, above the title, on the surface where the title is the point.
    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            completionButton
            // No confirmation: the delete happens and ⌘Z is the way back.
            // Both roots re-read `selectedTask`, so the panel follows the
            // selection onto the neighbouring card instead of holding this one.
            Button(role: .destructive) { store.trashTask(task.id) } label: {
                glyph("trash")
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: metrics.headerButtonRadius)
            .help("Trash task")
            .accessibilityLabel("Trash task")
            Button { close() } label: {
                glyph("xmark")
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: metrics.headerButtonRadius)
            .accessibilityLabel("Close details")
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, 16)
    }

    /// A symbol in the header's square. The square is what the pointer and the
    /// finger get, so it is the frame rather than the glyph that is sized to
    /// `headerButton`, and `.contentShape` is what makes the empty corners of
    /// it live.
    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .symbolSize(metrics.headerGlyph, weight: .semibold, relativeTo: .body)
            .foregroundStyle(palette.inkText(0.5))
            .frame(minWidth: chrome(metrics.headerButton), minHeight: chrome(metrics.headerButton))
            .contentShape(.rect)
    }

    /// The first of the three, and the only one that is not a glyph: it is the
    /// card's own tick, drawn as `CompletionToggle` draws it everywhere else.
    ///
    /// **It is the card's tick, not a second verb.** It calls
    /// `toggleCompletion`, which is what the circle in the card's gutter, the
    /// first item in its context menu and ⌘↩ all call: completing a card *is*
    /// moving it to its board's Done column — the rightmost column on every
    /// board this app seeds — so there is one rule and this is another door
    /// onto it. Pressing it again reopens the card, for the same reason the
    /// card's does: a tick a finger cannot take back is a trap.
    ///
    /// A shape rather than a `checkmark` glyph because it has to say whether
    /// the card *is* done as well as offer to finish it, and the drawn box is
    /// the app's one answer to that question. Its `hitSize` is the header's
    /// square, so the toggle claims exactly what its neighbours do.
    ///
    /// Drawn on anything that is not archived — in the Archive the verb is
    /// Restore and only Restore, which is the card's own button and not this
    /// panel's. Disabled rather than hidden when there is nowhere to complete
    /// *to*: a board can arrive from a hand-edited file with no Done column at
    /// all, and a control that vanishes on one card and not the next reads as
    /// a bug rather than as a board missing a column.
    @ViewBuilder private var completionButton: some View {
        if !task.isArchived {
            let isEnabled = store.canToggleCompletion(task.id)
            CompletionToggle(isDone: store.isDone(task), metrics: metrics.tick) {
                store.toggleCompletion(task.id)
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
            .hoverBackground(palette.ink(0.08), radius: metrics.headerButtonRadius)
            .help(store.isDone(task) ? "Reopen task" : "Complete task")
        }
    }

    // MARK: Editable text

    /// A title is one line. On a vertical-axis field Return inserts a newline
    /// and `.onSubmit` never fires, so a pasted paragraph became a title the
    /// board card had no room to draw. Dropping the axis makes Return end the
    /// session — one activity entry, and the field gives focus back.
    private var titleField: some View {
        TextField("Task title", text: binding(.title))
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.serif(metrics.titleSize))
            .lineSpacing(3)
            .foregroundStyle(palette.ink)
            .focused($focusedField, equals: .title)
            .onSubmit { focusedField = nil }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldHitArea(minHeight: metrics.fieldHit) { focusedField = .title }
            .accessibilityLabel("Title")
    }

    private var noteField: some View {
        TextField("Add a description", text: binding(.note), axis: .vertical)
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.ui(metrics.noteSize, .medium, relativeTo: .subheadline))
            .lineSpacing(4)
            .foregroundStyle(palette.ink(0.62))
            .focused($focusedField, equals: .note)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldHitArea(minHeight: metrics.fieldHit) { focusedField = .note }
            .accessibilityLabel("Description")
    }

    private func binding(_ field: TaskField) -> Binding<String> {
        Binding(
            get: { store.text(field, on: task.id) },
            set: { store.setText($0, field: field, on: task.id) }
        )
    }

    // MARK: Attributes

    /// Which board the card is on, and then where on it. Two controls because
    /// they are two questions: the picker below draws one board's columns, so
    /// without this a card could only ever move inside the board it was already
    /// on — and a card in the Inbox is on none. The menu is also the only way
    /// back to the Inbox, which is why it is not the picker's first segment.
    ///
    /// Which is also why the second question can go unasked. The card's own
    /// board and nothing else: set the menu to Inbox and the columns underneath
    /// go, because there is no board left for them to be the columns of.
    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status").sectionLabelStyle(size: 10.5, opacity: Palette.readableInk)
            BoardDestinationMenu(task: task, metrics: metrics.destination)
            MoveToPicker(
                board: store.board(for: task),
                currentColumnID: task.columnID, metrics: metrics.moveTo
            ) { placement in
                store.move(task.id, to: placement)
            }
        }
    }

    private var attributes: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow(alignment: .center) {
                fieldName("Due")
                DueDateField(task: task, scope: .desk, metrics: metrics.due)
            }
            GridRow(alignment: .center) {
                fieldName("Priority")
                PriorityPicker(task: task, scope: .desk, metrics: metrics.priority)
            }
            GridRow(alignment: .top) {
                fieldName("Labels")
                LabelEditor(task: task, scope: .desk, metrics: metrics.labels)
            }
        }
    }

    /// The grid's first column. A *minimum* rather than a width: 84pt is two
    /// words at the default size and "Priority" broken across two lines as
    /// "Prio / rity" at AX5. `Grid` sizes the column to the widest cell, so the
    /// three names stay aligned however wide they grow.
    private func fieldName(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(SimpleKanbanFont.ui(metrics.fieldNameSize, .bold, relativeTo: .footnote))
            .foregroundStyle(palette.inkText(0.42))
            .frame(minWidth: metrics.fieldNameWidth, alignment: .leading)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Checklist").sectionLabelStyle(size: 10.5, opacity: Palette.readableInk)
                ProgressMeter(fraction: task.subtaskFraction, height: 4)
                Text(task.subtaskProgressText)
                    .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                    .foregroundStyle(palette.inkText(0.45))
            }
            ChecklistView(task: task, scope: .desk, metrics: metrics.checklist)
        }
    }

    /// The list itself is `ActivityFeed`, shared with the iOS sheet, which had
    /// no history section at all — the same task showed its past on one
    /// platform and hid it on the other.
    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity").sectionLabelStyle(size: 10.5, opacity: Palette.readableInk)
            ActivityFeed(task: task, metrics: metrics.activity)
        }
    }
}
