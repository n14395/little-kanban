import SwiftUI

/// The app's own face: the one it is wearing, the ten it can wear, and the
/// switch that hands the choice to the theme.
///
/// **A surface of its own rather than rows on the Settings pane.** Every other
/// row there is a line of text and a control; this is a picture the size of a
/// Dock icon with a grid of ten more under it, and a panel holding that inside
/// a list of switches is not a group — it is a page that has been folded into a
/// row. So *Appearance* carries a row that names the current icon and opens
/// this, exactly as it carries one that names the two themes and opens the
/// browser.
///
/// **A sheet on both platforms**, where ``ThemeBrowserView`` is a window on the
/// desk. The browser is a grid of pictures of the whole app and comparing two of
/// them across a wide window is what it is for; this is one hero, ten tiles and
/// a switch, at a size that does not change if it is given more room. A window
/// for it would be a window that is mostly empty.
struct AppIconPickerView: View {
    struct Metrics: Sendable {
        /// Fixed on the desk, where a sheet is as wide as it is told to be, and
        /// `nil` in the phone's, which is as wide as the phone.
        var width: CGFloat?
        var minHeight: CGFloat?
        var padding: CGFloat
        var titleSize: CGFloat
        var nameSize: CGFloat
        var noteSize: CGFloat
        /// The icon at something near the size it is worn at.
        var heroSize: CGFloat
        var tileSize: CGFloat
        var hit: CGFloat

        static let desk = Metrics(
            width: 480, minHeight: 540, padding: 24, titleSize: 20,
            nameSize: 14, noteSize: 11.5, heroSize: 128, tileSize: 62, hit: 28
        )
        static let sheet = Metrics(
            width: nil, minHeight: nil, padding: 18, titleSize: 20,
            nameSize: 15, noteSize: 12.5, heroSize: 120, tileSize: 56, hit: 44
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Preferences.appIconKey) private var gradientID = AppIcon.defaultID
    @AppStorage(Preferences.appIconFollowsThemeKey) private var followsTheme = false

    var metrics: Metrics = .sheet

    var body: some View {
        VStack(spacing: 0) {
            header.hairline(.bottom, color: palette.ink(0.08))
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    grid
                    followsThemeRow
                }
                .padding(metrics.padding)
            }
        }
        .frame(width: metrics.width)
        .frame(minHeight: metrics.minHeight, maxHeight: .infinity)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Text("App icon")
                .font(palette.display(metrics.titleSize))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            // A sheet needs a way out that is not the Escape key, on both
            // platforms: this one has no title bar of its own to close from.
            Button { dismiss() } label: {
                Text("Done")
                    .font(palette.ui(metrics.nameSize, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: metrics.hit)
                    .background(palette.accent, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.bare)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, 14)
    }

    // MARK: What is being worn

    /// The icon as it **resolves**, not as the grid was left.
    ///
    /// With the switch at the bottom on, this is the theme's icon and none of
    /// the ten below is lit — which is the only thing on the page that says
    /// which of the two controls is in charge. `palette.theme` rather than a
    /// second read of the appearance: the palette this page is drawn with was
    /// built from the theme in force, so its slot is the one to resolve against.
    private var resolved: ResolvedAppIcon {
        AppIcon.resolve(
            AppIconSelection(gradientID: gradientID, followsTheme: followsTheme),
            themes: store.themes,
            appearance: palette.theme.appearance
        )
    }

    private var hero: some View {
        VStack(spacing: 14) {
            AppIconTile(art: resolved.art, size: metrics.heroSize)
            VStack(spacing: 3) {
                Text(resolved.name)
                    .font(palette.ui(metrics.nameSize + 2, .bold, relativeTo: .headline))
                    .foregroundStyle(palette.ink)
                Text(sourceNote)
                    .font(palette.ui(metrics.noteSize, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
                #if os(macOS)
                // Said here because the alternative is somebody choosing an
                // icon, quitting, and finding the old one in Finder and calling
                // it broken. `applicationIconImage` is the Dock icon of a
                // *running* app; the bundle's own is what a sandboxed app
                // cannot rewrite. See ``AppIconInstaller``.
                Text("Shown in the Dock while Simple Kanban is running.")
                    .font(palette.ui(metrics.noteSize, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.34))
                #endif
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var sourceNote: String {
        followsTheme
            ? String(localized: "Follows the theme, and changes with it.",
                     comment: "Note under the app icon when it is theme-matched")
            : String(localized: "The same icon whatever the theme.",
                     comment: "Note under the app icon when it is one of the ten")
    }

    // MARK: The ten

    /// Five fixed columns rather than an adaptive grid: ten tiles laid out
    /// adaptively come out eight and two on the desk and four, four and two on a
    /// phone, and a picker whose rows change length as the sheet resizes reads
    /// as a list that has lost its place. Two rows of five is the shape the set
    /// actually has.
    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 14
        ) {
            ForEach(AppIcon.all) { icon in
                Button { gradientID = icon.id } label: {
                    AppIconTile(
                        art: icon.art, size: metrics.tileSize,
                        isCurrent: !followsTheme && icon.id == gradientID
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.bare)
                .help(icon.name)
                .accessibilityLabel(icon.name)
                .accessibilityAddTraits(icon.id == gradientID ? [.isSelected] : [])
            }
        }
        // **Dimmed and dead, not hidden.** With the switch below turned on the
        // theme decides, and a grid that still took clicks would be ten controls
        // doing nothing visible. The ring is off all ten for the same reason:
        // none of them is what the app is wearing.
        .opacity(followsTheme ? 0.35 : 1)
        .disabled(followsTheme)
        .accessibilityHidden(followsTheme)
    }

    // MARK: The switch

    private var followsThemeRow: some View {
        Toggle(isOn: $followsTheme) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Icon follows app theme")
                    .font(palette.ui(metrics.nameSize, .semibold, relativeTo: .subheadline))
                Text("The theme's window gradient, highlight and ink, drawn as the icon.")
                    .font(palette.ui(metrics.noteSize, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(minHeight: metrics.hit)
        .background(palette.card, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(palette.ink(0.07), lineWidth: 1)
        }
    }
}
