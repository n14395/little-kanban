import SwiftUI
import UniformTypeIdentifiers

/// The twenty themes the app ships with, and the ones the user has made.
///
/// **All twenty are always on show, and there is no light/dark mode to switch
/// between.** A tile goes into the slot its own appearance names — press
/// Porcelain and the light slot becomes Porcelain, press Ember and the dark slot
/// becomes Ember — so a person can set both halves of the app from one page and
/// cannot put a dark theme where a light one belongs. The pair in use is named
/// at the top, and the tiles wearing them are ringed.
///
/// Each tile is a small picture of the app rather than a row of swatches: a
/// theme is a ground, two faces, a card and eight colours working together, and
/// six circles say almost nothing about how that comes out. See
/// ``ThemePreviewTile``.
struct ThemeBrowserView: View {
    struct Metrics: Sendable {
        var width: CGFloat?
        /// A sheet on macOS is only as tall as it is told to be, and a grid of
        /// twenty pictures in a 420pt window is a keyhole.
        var minHeight: CGFloat?
        var padding: CGFloat
        var titleSize: CGFloat
        var nameSize: CGFloat
        var noteSize: CGFloat
        var tileScale: CGFloat
        var columnWidth: CGFloat
        var hit: CGFloat
        var editor: ThemeEditorView.Metrics

        // Two 248pt tiles, their gap, the padding and the scroller — 560 is
        // ten points short of that once macOS takes its bar, and the grid drops
        // to a single column. It is presented over the 520pt Settings pane, so
        // it stays as close to that as two columns allow.
        static let desk = Metrics(
            width: 640, minHeight: 560, padding: 20, titleSize: 18, nameSize: 13, noteSize: 11,
            tileScale: 1, columnWidth: 248, hit: 28, editor: .desk
        )
        static let sheet = Metrics(
            width: nil, minHeight: nil, padding: 16, titleSize: 20, nameSize: 15, noteSize: 12.5,
            tileScale: 1, columnWidth: 248, hit: 44, editor: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var metrics: Metrics = .desk

    @State private var editing: Theme?
    @State private var exporting: Theme?
    @State private var deleting: Theme?
    @State private var isImporting = false
    @State private var importFailure: String?

    var body: some View {
        VStack(spacing: 0) {
            header.hairline(.bottom, color: palette.ink(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inUse
                    grid
                }
                .padding(metrics.padding)
            }
        }
        .frame(width: metrics.width)
        .frame(minHeight: metrics.minHeight, maxHeight: .infinity)
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
                Button(String(localized: "New Light Theme", comment: "Menu item: starts a new theme for the light slot")) {
                    editing = blank(.light)
                }
                Button(String(localized: "New Dark Theme", comment: "Menu item: starts a new theme for the dark slot")) {
                    editing = blank(.dark)
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

            Button { dismiss() } label: {
                Text("Done")
                    .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(palette.accent, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, 12)
    }

    /// The pair in force, named. Two lines rather than a badge on the tiles
    /// alone: at any moment one of the two is the one you are *looking* at and
    /// the other is not, and a person changing the dark theme in daylight has no
    /// other way to see that anything happened.
    private var inUse: some View {
        HStack(spacing: 10) {
            ForEach(ThemeAppearance.allCases) { appearance in
                let theme = store.theme(for: appearance)
                HStack(spacing: 8) {
                    Image(systemName: appearance == .dark ? "moon.fill" : "sun.max.fill")
                        .font(palette.ui(metrics.noteSize, .bold, relativeTo: .caption))
                        .foregroundStyle(palette.inkText(0.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appearance.label)
                            .sectionLabelStyle(size: metrics.noteSize - 1.5)
                        Text(theme.name)
                            .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                            .foregroundStyle(palette.ink)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.card, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(palette.ink(0.07), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: metrics.columnWidth), spacing: 14, alignment: .top)],
            spacing: 16
        ) {
            ForEach(store.themes.all) { theme in
                tile(theme)
            }
        }
    }

    private func tile(_ theme: Theme) -> some View {
        let isCurrent = store.themes.id(for: theme.appearance) == theme.id
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                store.selectTheme(theme)
            } label: {
                ThemePreviewTile(theme: theme, scale: metrics.tileScale)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isCurrent ? palette.accent : .clear, lineWidth: 2.5)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
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
        .frame(width: 248 * metrics.tileScale, alignment: .leading)
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
    /// anybody does with one is fill it in with something that works, and Ember
    /// and Porcelain already do.
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
                if let first = landed.first { store.selectTheme(first) }
            } catch {
                importFailure = error.localizedDescription
            }
        }
    }
}
