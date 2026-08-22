import Foundation
import Testing
@testable import Simple_Kanban

/// Contract §9: every interactive control in `Sources/Shared/` carries its own
/// hit metric, and the touch preset claims at least 44pt.
///
/// These read the metrics rather than a rendered layout on purpose. The two
/// defects this suite exists for — a 28pt colour swatch and a 30pt checklist
/// box — were both a `Metrics` constant that nobody could see was too small,
/// and a constant is exactly what a later edit puts back.
@Suite struct TouchTargetTests {

    /// Apple's minimum. Named so a failure says what the number is for.
    private static let finger: CGFloat = 44

    @Test func everyTouchPresetClaimsAFingersWorth() {
        let targets: [(String, CGFloat)] = [
            ("CompletionToggle.sheet.hitSize", CompletionToggle.Metrics.sheet.hitSize),
            ("CompletionToggle.sheetRow.hitSize", CompletionToggle.Metrics.sheetRow.hitSize),
            ("LabelManagerView.sheet.swatchHit", LabelManagerView.Metrics.sheet.swatchHit),
            ("LabelManagerView.sheet.glyphHit", LabelManagerView.Metrics.sheet.glyphHit),
            ("LabelManagerView.sheet.rowMinHeight", LabelManagerView.Metrics.sheet.rowMinHeight),
            ("AccentPicker.drawer.swatchHit", AccentPicker.Metrics.drawer.swatchHit),
            ("LabelEditor.sheet.addHit", LabelEditor.Metrics.sheet.addHit),
            ("LabelPickerList.sheet.rowHit", LabelPickerList.Metrics.sheet.rowHit),
            ("DueDateField.sheet.chipHit", DueDateField.Metrics.sheet.chipHit),
            ("DueDateField.sheet.rowHit", DueDateField.Metrics.sheet.rowHit),
            ("PriorityPicker.sheet.hit", PriorityPicker.Metrics.sheet.hit),
            ("MoveToPicker.sheet.itemHit", MoveToPicker.Metrics.sheet.itemHit),
            ("LabelManagerView.sheet.fieldHit", LabelManagerView.Metrics.sheet.fieldHit),
            ("ChecklistView.sheet.rowMinHeight", ChecklistView.Metrics.sheet.rowMinHeight),
            ("ChecklistView.sheet.fieldHit", ChecklistView.Metrics.sheet.fieldHit),
            ("ChecklistView.sheet.box.hitSize", ChecklistView.Metrics.sheet.box.hitSize),
            ("EmptyStateView.sheet.actionHit", EmptyStateView.Metrics.sheet.actionHit),
            ("SettingsView.sheet.rowHit", SettingsView.Metrics.sheet.rowHit),
            // The iPad draws the desk's board at touch sizes, so `.pad` is a
            // touch preset and belongs here beside `.sheet`. Measured on a
            // booted iPad too — see the iPad section of the README — but a
            // measurement is a run and this is the constant it came from.
            ("BoardTaskCard.pad.toggle.hitSize", BoardTaskCard.Metrics.pad.toggle.hitSize),
            ("BoardTaskCard.pad.restoreHit", BoardTaskCard.Metrics.pad.restoreHit),
            ("BoardColumnView.pad.headerButton", BoardColumnView.Metrics.pad.headerButton),
            ("BoardColumnView.pad.rowHit", BoardColumnView.Metrics.pad.rowHit),
            ("BoardColumnView.ColumnEditorMetrics.pad.fieldHit",
             BoardColumnView.ColumnEditorMetrics.pad.fieldHit),
            ("BoardColumnView.ColumnEditorMetrics.pad.fieldHeight",
             BoardColumnView.ColumnEditorMetrics.pad.fieldHeight),
            ("BoardSidebar.pad.rowHit", BoardSidebar.Metrics.pad.rowHit),
            ("BoardSidebar.pad.fieldHit", BoardSidebar.Metrics.pad.fieldHit),
            ("BoardToolbar.pad.control", BoardToolbar.Metrics.pad.control),
            ("BoardToolbar.pad.fieldHit", BoardToolbar.Metrics.pad.fieldHit),
            ("TaskInspector.pad.headerButton", TaskInspector.Metrics.pad.headerButton),
            ("TaskInspector.pad.fieldHit", TaskInspector.Metrics.pad.fieldHit),
        ]
        for (name, claim) in targets {
            #expect(claim >= Self.finger, "\(name) is \(claim)pt; a finger needs \(Self.finger)")
        }
    }

    /// The pointer presets are the other half of the rule: raising a touch
    /// target must not drag the desk's geometry with it. A `.desk` hit metric
    /// claims what its control draws, or nothing at all — `frame(minWidth: 0)`
    /// and `padding(-0)` are exact no-ops, which is what keeps macOS unchanged.
    @Test func noPointerPresetInflatesTheDesk() {
        #expect(ChecklistView.Metrics.desk.boxOverhang == 0)
        #expect(ChecklistView.Metrics.desk.rowMinHeight == 0)
        #expect(ChecklistView.Metrics.desk.fieldHit == 0)
        #expect(LabelManagerView.Metrics.desk.fieldHit == 0)
        #expect(DueDateField.Metrics.desk.chipHit == 0)
        #expect(DueDateField.Metrics.desk.rowHit == 0)
        #expect(LabelEditor.Metrics.desk.addHit == 0)
        #expect(LabelPickerList.Metrics.desk.rowHit == 0)
        #expect(PriorityPicker.Metrics.desk.hit == 0)
        #expect(MoveToPicker.Metrics.desk.itemHit == 0)
        #expect(EmptyStateView.Metrics.desk.actionHit == 0)
        // The desk's settings pane sits in a window that already has a title
        // bar, and its rows are a line of text and a control.
        #expect(SettingsView.Metrics.desk.rowHit == 0)

        // The board's own presets, which is the claim the iPad extraction
        // rests on: `.pad` raised every one of these and `.desk` still applies
        // no modifier at all, so macOS renders what it rendered.
        #expect(BoardTaskCard.Metrics.desk.restoreHit == 0)
        #expect(BoardColumnView.Metrics.desk.rowHit == 0)
        #expect(BoardColumnView.ColumnEditorMetrics.desk.fieldHit == 0)
        #expect(BoardSidebar.Metrics.desk.rowHit == 0)
        #expect(BoardSidebar.Metrics.desk.fieldHit == 0)
        #expect(BoardToolbar.Metrics.desk.fieldHit == 0)
        #expect(TaskInspector.Metrics.desk.fieldHit == 0)
        // The two that claim rather than pass, both the extent already drawn.
        #expect(BoardColumnView.Metrics.desk.headerButton < Self.finger)
        #expect(TaskInspector.Metrics.desk.headerButton < Self.finger)
        // The desk names the side its column popover hangs off; the iPad names
        // none, because its header sits 134pt from the top of the display and a
        // popover pinned above it opened off the screen — see
        // `ColumnEditorMetrics.arrowEdge`.
        #expect(BoardColumnView.ColumnEditorMetrics.desk.arrowEdge != nil)
        #expect(BoardColumnView.ColumnEditorMetrics.pad.arrowEdge == nil)

        // The three that claim rather than pass: each is the extent the control
        // already draws, so the square is the shape and not a bigger one.
        let desk = CompletionToggle.Metrics.desk
        #expect(desk.hitSize >= desk.size && desk.hitSize < Self.finger)
        let deskRow = CompletionToggle.Metrics.deskRow
        #expect(deskRow.hitSize >= deskRow.size && deskRow.hitSize < Self.finger)
        let manager = LabelManagerView.Metrics.desk
        #expect(manager.swatchHit >= manager.swatch && manager.swatchHit < Self.finger)
        let accent = AccentPicker.Metrics.desk
        #expect(accent.swatchHit >= accent.swatch && accent.swatchHit < Self.finger)
    }

    /// §9's negative-padding clause. The checklist box claims 44 and hands the
    /// difference straight back, so the row keeps the height and the text
    /// position it draws today — and the square still lands inside the row,
    /// because hit-testing does not follow a view outside an ancestor.
    @Test func theChecklistBoxGivesBackWhatItsTargetTook() {
        let sheet = ChecklistView.Metrics.sheet
        let claimed = sheet.box.hitSize - 2 * sheet.boxOverhang
        // Every one of these holds at an overhang of zero, which is the shape
        // this test exists to catch: without the pull-back the 44pt square takes
        // its full width in the row and pushes the text across.
        #expect(sheet.boxOverhang > 0, "the 44pt square is not being pulled back at all")
        #expect(claimed < sheet.box.hitSize, "the overhang gives nothing back")
        #expect(claimed >= sheet.box.size, "the overhang has eaten into the drawn box")
        #expect(claimed <= sheet.rowMinHeight, "the box is pushing the row taller than it draws")
        #expect(sheet.box.hitSize <= sheet.rowMinHeight, "the 44pt square spills outside the row")
    }

    /// §6's truncation cap on a chip's name — a `Metrics`-shaped constant in
    /// everything but its name, and read here for the same reason as the rest.
    ///
    /// `.lineLimit(1)` on its own only stops a long name wrapping; the width is
    /// what stops it taking a whole `FlowLayout` line to itself and pushing the
    /// row below it down. The regression is a ceiling of `.infinity`, which
    /// renders identically until someone names a label the long way.
    @Test func aLabelChipsNameCannotOutgrowItsRow() {
        let phone: CGFloat = 375
        for size in [LabelChip.Size.compact, .comfortable] {
            #expect(size.maxNameWidth.isFinite, "an uncapped name takes the whole line")
            #expect(size.maxNameWidth > 0)
            // Two chips have to fit one line of the narrowest phone, or the cap
            // has bought nothing: a row of them is what it is there to protect.
            let chip = size.maxNameWidth + 2 * size.horizontalPadding
            #expect(2 * chip <= phone, "\(chip)pt of chip twice over does not fit \(phone)pt")
        }
        // The ceilings themselves, because a constant is what a later edit puts
        // back: touch type runs larger, so the touch ceiling does too.
        #expect(LabelChip.Size.compact.maxNameWidth == 132)
        #expect(LabelChip.Size.comfortable.maxNameWidth == 168)
        #expect(LabelChip.Size.comfortable.maxNameWidth > LabelChip.Size.compact.maxNameWidth)

        // The width alone only clips; a name still has to be held to one line
        // and told where to break, or it wraps inside the ceiling instead.
        for size in [LabelChip.Size.compact, .comfortable] {
            #expect(size.nameLineLimit == 1)
            #expect(size.nameTruncation == .tail)
        }

        // The remove control is drawn on the pointer surface only; touch carries
        // the same action on a long press and reserves no room for it.
        #expect(LabelChip.Size.compact.revealsRemoveOnHover)
        #expect(LabelChip.Size.comfortable.revealsRemoveOnHover == false)
    }

    /// Where 44pt targets and the design's gaps cannot both fit the narrowest
    /// supported phone, §9 says the targets win and the spacing gives way.
    /// Both of these are a row of round swatches, which is where that bites.
    @Test func theSwatchRowsFitTheNarrowestPhone() {
        let phone: CGFloat = 375

        let manager = LabelManagerView.Metrics.sheet
        let swatches = CGFloat(LabelDef.palette.count)
        let colourRow = swatches * manager.swatchHit + (swatches - 1) * manager.swatchSpacing
        let colourBudget = phone - 2 * manager.panelPadding - 2 * manager.rowPadding
        #expect(colourRow <= colourBudget, "\(colourRow)pt of swatches in \(colourBudget)pt of row")

        let accent = AccentPicker.Metrics.drawer
        let themes = CGFloat(AccentTheme.allCases.count)
        // The word "Accent" and its `Spacer` share the line, so the swatches get
        // what is left of the drawer rather than all of it.
        let accentRow = themes * accent.swatchHit + (themes - 1) * accent.spacing
        #expect(accentRow <= phone / 2, "\(accentRow)pt of swatches crowds the label off the row")

        // The board editor's row is drawn in `Sources/IOS`, so its geometry is
        // out of this target's reach and only the count it is sized against can
        // be pinned here: six 44pt targets, butted up with no spacing left to
        // give away. A seventh colour is what breaks it, silently, on the
        // narrowest phone only.
        let dots = CGFloat(Board.dotPalette.count)
        #expect(Board.dotPalette.count == 6)
        #expect(dots * 44 <= phone, "\(dots * 44)pt of board swatches does not fit \(phone)pt")
    }

    /// One palette for both surfaces, or a board coloured on the phone cannot be
    /// put back to that colour on the desk. The seed workflow's own dots have to
    /// be in it for the same reason: a column recoloured by accident is only
    /// undoable while the swatch it arrived with is still on offer.
    @Test func theBoardAndColumnSwatchesCoverWhatTheSeedShipsWith() {
        #expect(Set(BoardColumn.workflow.map(\.dot)).isSubset(of: Set(Board.dotPalette)))
        #expect(Board.dotPalette.contains(SeedData.defaultBoard.dot))
        // The Inbox's grey is not a choice: a board wearing it sits in the same
        // sidebar list as the Inbox itself.
        #expect(Board.dotPalette.contains(Board.inboxDot) == false)
        #expect(Set(Board.dotPalette).count == Board.dotPalette.count)
    }

    /// **No swatch is announced by its position.** Both rows had "Colour 1"
    /// through "Colour 6" for a name, which tells a VoiceOver user where the
    /// button is and nothing about what pressing it does. The names live beside
    /// the colours on the model, so a picker cannot go on drawing a swatch the
    /// model has no word for, and a swatch and its name cannot drift apart.
    @Test func everySwatchOnOfferCarriesAName() {
        for dot in Board.dots {
            #expect(dot.name.isEmpty == false)
        }
        for tone in LabelDef.tones {
            #expect(tone.name.isEmpty == false)
        }
        #expect(Set(Board.dots.map(\.name)).count == Board.dots.count, "two dots share a name")
        #expect(Set(LabelDef.tones.map(\.name)).count == LabelDef.tones.count, "two tones share a name")

        // The derived lists the rest of the app takes are exactly these, in this
        // order — a name added to one and not the other would be a picker
        // labelling the wrong swatch rather than a compile error.
        #expect(Board.dotPalette == Board.dots.map(\.swatch))
        #expect(LabelDef.palette.map(\.light) == LabelDef.tones.map(\.light))
        #expect(LabelDef.palette.map(\.dark) == LabelDef.tones.map(\.dark))
    }
}
