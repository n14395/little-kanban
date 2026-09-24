import SwiftUI
import UniformTypeIdentifiers

/// The twenty themes the app ships with, and the ones the user has made.
///
/// **One control does two jobs at the top.** The pair of buttons names the theme
/// in each slot *and* chooses which half of the catalogue is below them: press
/// Dark and the grid is the eleven dark themes, press Light and it is the nine
/// light ones. Twenty pictures in one scroll is a lot of scrolling to compare
/// two dark grounds that are nine tiles apart, and the two halves are never
/// alternatives to each other — a light theme and a dark one are both in use.
///
/// A tile still goes into the slot its own appearance names, which under the
/// filter is simply the slot named on the lit button. It is not possible to put
/// a dark theme where a light one belongs.
///
/// Each tile is a small picture of the app rather than a row of swatches: a
/// theme is a ground, two faces, a card and eight colours working together, and
/// six circles say almost nothing about how that comes out. See
/// ``ThemePreviewTile``.
struct ThemeBrowserView: View {
    struct Metrics: Sendable {
        /// Fixed for a sheet, which is as wide as it is told to be, and `nil` for
        /// the desk's window, which is the user's to resize — the grid is
        /// adaptive, so a wider window is more columns rather than wider tiles.
        var width: CGFloat?
        /// The floor a resizable window may not go below: one tile and its
        /// padding. Under that the grid has nothing to lay out.
        var minWidth: CGFloat?
        /// A sheet on macOS is only as tall as it is told to be, and a grid of
        /// pictures in a 420pt window is a keyhole.
        var minHeight: CGFloat?
        /// A sheet needs a way out that is not the Escape key. A window has a
        /// close button in its own title bar, and a Done button beside that is a
        /// second door to the same room.
        var showsDone: Bool
        var padding: CGFloat
        var titleSize: CGFloat
        var nameSize: CGFloat
        var noteSize: CGFloat
        var tileScale: CGFloat
        var columnWidth: CGFloat
        var hit: CGFloat
        var editor: ThemeEditorView.Metrics

        /// A window of its own on the desk — see the `themes` scene in
        /// `LittleKanbanApp`. No fixed width: three columns at the size it opens
        /// at, more if it is dragged wider, one at the floor.
        static let window = Metrics(
            width: nil, minWidth: 336, minHeight: 460, showsDone: false, padding: 24,
            titleSize: 20, nameSize: 14, noteSize: 11.5,
            tileScale: 1, columnWidth: 248, hit: 28, editor: .desk
        )
        static let sheet = Metrics(
            width: nil, minWidth: nil, minHeight: nil, showsDone: true, padding: 16,
            titleSize: 20, nameSize: 15, noteSize: 12.5,
            tileScale: 1, columnWidth: 248, hit: 44, editor: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var metrics: Metrics = .sheet

    /// Which half of the catalogue is on show. `nil` until somebody presses one
    /// of the two, and until then it is *the appearance in force* — you land on
    /// the themes you can see, which is the half you came here to change.
    @State private var chosenSlot: ThemeAppearance?

    @State private var editing: Theme?
    @State private var exporting: Theme?
    @State private var deleting: Theme?
    @State private var isImporting = false
    @State private var importFailure: String?
    /// The width the grid actually has, for ``tileScale``. Zero until measured.
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header.hairline(.bottom, color: palette.ink(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    slotSwitch
                    grid
                }
                .padding(metrics.padding)
            }
        }
        .frame(width: metrics.width)
        .frame(minWidth: metrics.minWidth, minHeight: metrics.minHeight, maxHeight: .infinity)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
        .sheet(item: $editing) { theme in
            ThemeEditorView(theme: theme, metrics: metrics.editor) { saved in
                store.saveTheme(saved)
                store.selectTheme(saved)
            }
            .environment(\.palette, palette)
            .environment(store)
        }
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: ThemeDocument(exporting.map { [$0] } ?? []),
            contentType: .json,
            defaultFilename: exporting.map(ThemeDocument.filename(for:))
        ) { _ in exporting = nil }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importThemes(from: result)
        }
        .alert(
            String(localized: "Delete this theme?", comment: "Alert title when removing a custom theme"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { theme in
            Button(String(localized: "Delete", comment: "Alert button: confirms removing a theme"), role: .destructive) {
                store.deleteTheme(theme.id)
            }
            Button(String(localized: "Cancel", comment: "Alert button: leaves the theme alone"), role: .cancel) {}
        } message: { theme in
            // Said plainly because it is the one act here that cannot be undone:
            // there is no ⌘Z on a settings surface, which is why this asks and
            // deleting a saved *colour* does not.
            Text("“\(theme.name)” cannot be brought back. Export it first if you might want it again.")
        }
        .alert(
            String(localized: "That theme could not be read.", comment: "Alert title when importing a theme fails"),
            isPresented: Binding(get: { importFailure != nil }, set: { if !$0 { importFailure = nil } }),
            presenting: importFailure
        ) { _ in
            Button(String(localized: "OK", comment: "Alert button: dismisses an error")) {}
        } message: { detail in
            Text(detail)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Text("Themes")
                .font(palette.display(metrics.titleSize))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            Menu {
                // One item rather than a light one and a dark one: the switch
                // above has already been asked that question, and a menu that
                // could make a theme the grid would then hide is a menu that
                // does nothing visible.
                Button(String(localized: "New Theme", comment: "Menu item: starts a new theme for the slot on show")) {
                    editing = blank(showing)
                }
                Divider()
                Button(String(localized: "Import…", comment: "Menu item: reads a theme in from a JSON file")) {
                    isImporting = true
                }
            } label: {
                Label(
                    String(localized: "Add", comment: "Menu button: new or imported theme"),
                    systemImage: "plus"
                )
                .labelStyle(.iconOnly)
                .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .frame(width: metrics.hit, height: metrics.hit)
                .contentShape(.rect)
            }
            .modifier(BorderlessMenu())
            .menuIndicator(.hidden)

            if metrics.showsDone {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(palette.accent, in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                }
                .bareButton()
            }
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, 12)
    }

    /// The two slots, as the one control that both names what is in them and
    /// decides which half of the catalogue is underneath.
    ///
    /// **Named, because only one of the two is ever on screen.** Somebody
    /// setting their dark theme in daylight sees nothing happen to the app; the
    /// lit button saying "Dark · Rainforest" is the only report they get. And it
    /// is a *filter* rather than a mode: both slots are in use at once, and
    /// nothing here is turned off by pressing the other one.
    private var slotSwitch: some View {
        HStack(spacing: 10) {
            ForEach(ThemeAppearance.allCases) { appearance in
                slotButton(appearance)
            }
        }
    }

    private func slotButton(_ appearance: ThemeAppearance) -> some View {
        let theme = store.theme(for: appearance)
        let isShowing = showing == appearance
        return Button { chosenSlot = appearance } label: {
            HStack(spacing: 8) {
                Image(systemName: appearance == .dark ? "moon.fill" : "sun.max.fill")
                    .font(palette.ui(metrics.noteSize, .bold, relativeTo: .caption))
                    .foregroundStyle(isShowing ? palette.accent : palette.inkText(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(appearance.label)
                        .sectionLabelStyle(size: metrics.noteSize - 1.5)
                    Text(theme.name)
                        .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: metrics.hit, alignment: .leading)
            .background(isShowing ? palette.accentSoft : palette.card, in: .rect(cornerRadius: 10))
            // Two points of accent rather than one of ink: the difference
            // between the two states has to survive a theme whose accent is a
            // pale gold on a pale ground.
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    isShowing ? palette.accent : palette.ink(0.07),
                    lineWidth: isShowing ? 2 : 1
                )
            }
            .contentShape(.rect)
        }
        .bareButton()
        .accessibilityLabel(appearance.label)
        .accessibilityValue(theme.name)
        .accessibilityHint(String(
            localized: "Shows the themes that can fill the \(appearance.label.lowercased()) slot",
            comment: "Accessibility hint on the light/dark filter buttons"
        ))
        .accessibilityAddTraits(isShowing ? [.isSelected] : [])
    }

    /// The half on show. See ``chosenSlot``.
    private var showing: ThemeAppearance { chosenSlot ?? palette.theme.appearance }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(themesOnShow) { theme in
                tile(theme)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    /// The half of the catalogue the grid draws: the slot's default first, then
    /// the rest in the document's order, then the user's own.
    ///
    /// **The default leads because it is the way back.** It is what a fresh
    /// install is wearing and the ground every other tile is implicitly
    /// compared against, and somebody who has wandered the grid should not have
    /// to remember which of twenty tiles undoes the wandering. The *model's*
    /// order is untouched — ``ThemePresets/all`` stays the document's, which is
    /// how the user counts them off the page — this is presentation only.
    private var themesOnShow: [Theme] {
        let half = store.themes.all.filter { $0.appearance == showing }
        let defaultID = ThemePresets.fallback(for: showing).id
        return half.filter { $0.id == defaultID } + half.filter { $0.id != defaultID }
    }

    /// Two tiles abreast on the phone, one column of full-size tiles at the
    /// desk-tile minimum everywhere else the width runs out.
    ///
    /// The phone's grid is two *fixed* columns rather than the adaptive row the
    /// other surfaces use, because adaptive fits full-size tiles and a 248pt
    /// tile fills a phone on its own — a single column of pictures is most of a
    /// screen per theme, and comparing two grounds meant scrolling between
    /// them. The tiles shrink to make the pair fit instead: see ``tileScale``.
    private var gridColumns: [GridItem] {
        isPhone
            ? Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: 2)
            : [GridItem(.adaptive(minimum: metrics.columnWidth), spacing: 14, alignment: .top)]
    }

    /// How far the phone's tiles shrink so two of them and their gutter span
    /// the grid exactly — capped at full size, which a landscape phone reaches.
    /// Until the width is measured the tiles draw at full size for one frame;
    /// the grid is already two columns, so nothing jumps between layouts.
    private var tileScale: CGFloat {
        guard isPhone, gridWidth > 0 else { return metrics.tileScale }
        return min(metrics.tileScale, (gridWidth - 14) / 2 / 248)
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private func tile(_ theme: Theme) -> some View {
        let isCurrent = store.themes.id(for: theme.appearance) == theme.id
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                store.selectTheme(theme)
            } label: {
                ThemePreviewTile(theme: theme, scale: tileScale)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isCurrent ? palette.accent : .clear, lineWidth: 2.5)
                    }
                    .contentShape(.rect)
            }
            .bareButton()
            .accessibilityLabel(theme.name)
            .accessibilityValue(theme.appearance.label)
            .accessibilityHint(String(localized: "Uses this theme for the \(theme.appearance.label.lowercased()) appearance",
                                      comment: "Accessibility hint on a theme tile"))
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])

            HStack(spacing: 6) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(palette.ui(metrics.noteSize, .bold, relativeTo: .caption))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name)
                        .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(theme.fontSummary)
                        .font(palette.ui(metrics.noteSize, .medium, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                menu(for: theme)
            }
        }
        .frame(width: 248 * tileScale, alignment: .leading)
    }

    private func menu(for theme: Theme) -> some View {
        Menu {
            Button(String(localized: "Edit…", comment: "Menu item: opens a theme in the editor")) {
                // A preset opens as a copy. It is a reference point, and one that
                // could be overwritten is not one — see `ThemeSettings.save(_:)`.
                editing = theme.isPreset
                    ? theme.duplicated(named: store.themes.unusedName(basedOn: theme.name))
                    : theme
            }
            Button(String(localized: "Duplicate", comment: "Menu item: copies a theme")) {
                let copy = theme.duplicated(named: store.themes.unusedName(basedOn: theme.name))
                store.saveTheme(copy)
            }
            Button(String(localized: "Export…", comment: "Menu item: writes a theme out as JSON")) {
                exporting = theme
            }
            if !theme.isPreset {
                Divider()
                Button(String(localized: "Delete", comment: "Menu item: removes a custom theme"), role: .destructive) {
                    deleting = theme
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
                .frame(width: metrics.hit, height: metrics.hit)
                .contentShape(.rect)
        }
        .modifier(BorderlessMenu())
        .menuIndicator(.hidden)
        .accessibilityLabel(String(localized: "Actions for \(theme.name)",
                                   comment: "Accessibility name of a theme's action menu"))
    }

    // MARK: Actions

    /// A new theme starts from the preset for its slot rather than from black.
    ///
    /// A form of thirty empty fields is not a starting point — the first thing
    /// anybody does with one is fill it in with something that works, and
    /// Aurora and Porcelain already do.
    private func blank(_ appearance: ThemeAppearance) -> Theme {
        var theme = ThemePresets.fallback(for: appearance)
            .duplicated(named: store.themes.unusedName(
                basedOn: String(localized: "My Theme", comment: "Default name for a newly made theme")
            ))
        theme.appearance = appearance
        return theme
    }

    private func importThemes(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importFailure = error.localizedDescription
        case .success(let url):
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            do {
                let landed = try ThemeDocument.decode(try Data(contentsOf: url))
                    .map(store.importTheme)
                // Selected as well as saved, and only the first: importing is
                // something somebody does in order to *use* a theme, and one
                // that landed silently in a grid of twenty-odd tiles would look
                // like nothing had happened.
                if let first = landed.first {
                    store.selectTheme(first)
                    // And show the half it belongs to, or an import of a dark
                    // theme while the light ones are on screen lands somewhere
                    // nobody can see.
                    chosenSlot = first.appearance
                }
            } catch {
                importFailure = error.localizedDescription
            }
        }
    }
}
