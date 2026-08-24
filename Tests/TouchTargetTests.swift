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

    /// The detail panel's header is one row of three controls — the tick, the
    /// trash, the ✕ — and what makes it read as a row rather than as three
    /// controls that happen to sit together is that all three claim the *same*
    /// square. Two of them are drawn straight off `headerButton`; the tick
    /// brings its own button and so its `hitSize` is the only place the
    /// agreement can be stated, which makes it the only place it can silently
    /// stop being true.
    @Test func theDetailPanelsThreeHeaderControlsClaimOneSquare() {
        for (name, metrics) in [("desk", TaskInspector.Metrics.desk), ("pad", TaskInspector.Metrics.pad)] {
            #expect(metrics.tick.hitSize == metrics.headerButton,
                    "the \(name) panel's tick no longer claims the square its neighbours do")
            // And the drawn box sits inside that square rather than filling or
            // overflowing it, which is what leaves room for the hover chip.
            #expect(metrics.tick.size < metrics.headerButton,
                    "the \(name) panel's tick is drawn as large as the square it sits in")
        }
    }

    @Test func everyTouchPresetClaimsAFingersWorth() {
        let targets: [(String, CGFloat)] = [
            ("CompletionToggle.sheet.hitSize", CompletionToggle.Metrics.sheet.hitSize),
            ("CompletionToggle.sheetRow.hitSize", CompletionToggle.Metrics.sheetRow.hitSize),
            // The tick on both touch detail surfaces, which now draw it in two
            // different places: the phone's beside the sheet's title, and the
            // iPad's in the inspector's header with the trash and the ✕ — named
            // twice there, once as the preset and once through the panel that
            // asks for it, because it is the panel's square it has to match.
            ("CompletionToggle.sheetPanel.hitSize", CompletionToggle.Metrics.sheetPanel.hitSize),
            ("CompletionToggle.sheetHeader.hitSize", CompletionToggle.Metrics.sheetHeader.hitSize),
            ("TaskInspector.pad.tick.hitSize", TaskInspector.Metrics.pad.tick.hitSize),
            ("LabelManagerView.sheet.swatchHit", LabelManagerView.Metrics.sheet.swatchHit),
            ("LabelManagerView.sheet.glyphHit", LabelManagerView.Metrics.sheet.glyphHit),
            ("LabelManagerView.sheet.rowMinHeight", LabelManagerView.Metrics.sheet.rowMinHeight),
            ("AccentPicker.drawer.swatchHit", AccentPicker.Metrics.drawer.swatchHit),
            ("LabelEditor.sheet.addHit", LabelEditor.Metrics.sheet.addHit),
            ("LabelPickerList.sheet.rowHit", LabelPickerList.Metrics.sheet.rowHit),
            ("DueDateField.sheet.chipHit", DueDateField.Metrics.sheet.chipHit),
            ("DueDateField.sheet.rowHit", DueDateField.Metrics.sheet.rowHit),
            // A day in the calendar is a control like any other. Only its
            // height is a number here — the width is a seventh of whatever the
            // panel is, which `MonthGridTests` is where to check.
            ("MonthGrid.sheet.cellHeight", MonthGrid.Metrics.sheet.cellHeight),
            ("MonthGrid.sheet.arrow", MonthGrid.Metrics.sheet.arrow),
            ("PriorityPicker.sheet.hit", PriorityPicker.Metrics.sheet.hit),
            ("MoveToPicker.sheet.itemHit", MoveToPicker.Metrics.sheet.itemHit),
            ("LabelManagerView.sheet.fieldHit", LabelManagerView.Metrics.sheet.fieldHit),
            ("ChecklistView.sheet.rowMinHeight", ChecklistView.Metrics.sheet.rowMinHeight),
            ("ChecklistView.sheet.fieldHit", ChecklistView.Metrics.sheet.fieldHit),
            ("ChecklistView.sheet.box.hitSize", ChecklistView.Metrics.sheet.box.hitSize),
            ("EmptyStateView.sheet.actionHit", EmptyStateView.Metrics.sheet.actionHit),
            ("SettingsView.sheet.rowHit", SettingsView.Metrics.sheet.rowHit),
            // The board's own settings, which both touch idioms draw at
            // `.sheet`: the iPad gets this sheet rather than the desk's, because
            // every control in it — the colour button, a step arrow, a field —
            // is one a finger has to land on.
            ("BoardSettingsView.sheet.hit", BoardSettingsView.Metrics.sheet.hit),
            // The colour control, and the popover it opens: the swatches in
            // there are the row `DotPicker` used to draw inline, at the same
            // 44 they always claimed.
            ("ColorWell.sheet.height", ColorWell.Metrics.sheet.height),
            ("ColorPickerPopover.sheet.swatchHit", ColorPickerPopover.Metrics.sheet.swatchHit),
            ("ColorPickerPopover.sheet.hit", ColorPickerPopover.Metrics.sheet.hit),
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
            // The bar's capture button, which is the iPad's alone — `nil` on the
            // desk, and force-unwrapped here rather than defaulted so that
            // taking it off the iPad has to be a decision made in this file too.
            ("BoardToolbar.pad.capture", BoardToolbar.Metrics.pad.capture!),
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
        // The calendar's desk cell is the one pointer metric here that is not
        // zero: it draws a row rather than padding one, and 28pt is what that
        // row is. What matters is that it stays well under the touch floor.
        #expect(MonthGrid.Metrics.desk.cellHeight < 44)
        #expect(MonthGrid.Metrics.desk.arrow < 44)
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
        // Being a pointer target is not a licence to be tiny: the desk's header
        // controls are the panel's three verbs and were raised to be hit
        // without aiming. Below this they are back to the 24pt squares they
        // were, which is the change this number records.
        #expect(TaskInspector.Metrics.desk.headerButton >= 32)
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
        let swatches = ColorPickerPopover.Metrics.desk
        #expect(swatches.swatchHit >= swatches.swatch && swatches.swatchHit < Self.finger)
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
    ///
    /// **A row of swatches is what bites, and there is one left.** The colour
    /// rows the boards, the columns and the labels each drew are one popover
    /// now — see ``ColorPickerPopover``, whose swatches wrap in a `FlowLayout`
    /// rather than being sized to a phone, because the palette is the user's
    /// and can be any length. What it *cannot* do is be wider than the phone it
    /// hangs off.
    @Test func theSwatchRowsFitTheNarrowestPhone() {
        let phone: CGFloat = 375

        let picker = ColorPickerPopover.Metrics.sheet
        #expect(picker.width <= phone - 16, "the picker is wider than the phone it opens on")
        // Four to a row at the narrowest, which is what a wrapping row needs to
        // be worth wrapping.
        let inner = picker.width - 2 * picker.spacing
        #expect(inner / picker.swatchHit >= 4, "the palette wraps to fewer than four across")

        let accent = AccentPicker.Metrics.drawer
        let themes = CGFloat(AccentTheme.allCases.count)
        // The word "Accent" and its `Spacer` share the line, so the swatches get
        // what is left of the drawer rather than all of it.
        let accentRow = themes * accent.swatchHit + (themes - 1) * accent.spacing
        #expect(accentRow <= phone / 2, "\(accentRow)pt of swatches crowds the label off the row")
    }

    /// One palette for every surface *and* every kind of thing, or a board
    /// coloured on the phone cannot be put back to that colour on the desk and a
    /// colour saved on a column cannot be given to a label. The seed workflow's
    /// own dots have to be in it for a related reason: a column recoloured by
    /// accident is only undoable while the swatch it arrived with is still on
    /// offer, and the seed is what a board file starts its palette with.
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
        for swatch in PaletteSwatch.seed {
            #expect(swatch.name?.isEmpty == false, "a shipped colour has no name")
            #expect(swatch.displayName.isEmpty == false)
        }
        #expect(Set(PaletteSwatch.seed.map(\.displayName)).count == PaletteSwatch.seed.count,
                "two shipped colours share a name")

        // **A colour the user mixed answers to its hex**, which is the honest
        // name for one nobody has named — and still not its position.
        #expect(PaletteSwatch(.hex(0x123456)).displayName == "#123456")
        // Unless it is one of the shipped ones added back by hand, which gets
        // the word it has always had.
        #expect(PaletteSwatch(.hex(0xC2532F)).displayName == "Ember")

        // The derived list the rest of the app takes is exactly this one, in
        // this order — a name added to one and not the other would be a picker
        // labelling the wrong swatch rather than a compile error.
        #expect(Board.dotPalette == Board.dots.map(\.swatch))
        #expect(PaletteSwatch.seed.map(\.swatch) == Board.dotPalette)
    }
}
