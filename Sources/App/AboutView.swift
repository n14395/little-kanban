import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the app is and which version of it this is.
///
/// The version was set in `project.yml` and shown nowhere; it is here, and the
/// copyright beside it is the string the macOS About panel would have shown if
/// the app had ever declared one.
///
/// On the desk this replaces the standard About panel, so there is exactly one
/// place the app talks about itself — and it is a window of its own rather than
/// a sheet on the board: a board window can hold one sheet, and on the launch
/// this most needs to survive the first-run picker is already using it.
/// On the phone it opens from the footer of Settings.
struct AboutView: View {
    struct Metrics {
        var width: CGFloat?
        var padding: CGFloat
        var spacing: CGFloat
        var icon: CGFloat
        var title: CGFloat
        var version: CGFloat
        var note: CGFloat
        var rowHit: CGFloat
        /// Whether the surface draws its own header. The desk's window has a
        /// title bar with a close button in it already; a sheet has neither.
        var showsHeader: Bool

        static let desk = Metrics(
            width: 380, padding: 24, spacing: 16, icon: 88, title: 26, version: 12,
            note: 11, rowHit: 0, showsHeader: false
        )
        static let sheet = Metrics(
            width: nil, padding: 22, spacing: 20, icon: 76, title: 32, version: 14.5,
            note: 12.5, rowHit: 44, showsHeader: true
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var metrics: Metrics = .desk

    var body: some View {
        VStack(spacing: 0) {
            if metrics.showsHeader {
                header.hairline(.bottom, color: palette.ink(0.08))
            }
            ScrollView {
                VStack(spacing: metrics.spacing) {
                    identity
                }
                .padding(metrics.padding)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: metrics.width)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("About", comment: "Title of the About surface")
                .font(palette.ui(17, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done", comment: "Closes the About surface")
                    .font(palette.ui(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: max(metrics.rowHit, 30))
            }
            .buttonStyle(.bare)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, metrics.padding * 0.6)
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: 6) {
            AppIconImage(size: metrics.icon)
            Text(Self.displayName)
                .font(palette.display(metrics.title))
                .foregroundStyle(palette.ink)
            Text(Self.versionLine)
                .font(palette.ui(metrics.version, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.ink(0.45))
                .textSelection(.enabled)
            if let copyright = UpdateChecker.copyright {
                Text(copyright)
                    .font(palette.ui(metrics.note, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.ink(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Simple Kanban"
    }

    /// "Version 1.0 (1)" — the marketing version people quote, and the build
    /// number that tells two builds of it apart in a bug report.
    static var versionLine: String {
        String(localized: "Version \(UpdateChecker.currentVersion) (\(UpdateChecker.buildNumber))",
               comment: "Marketing version and build number, shown in About")
    }

}

/// The app's own icon, read back out of the bundle rather than redrawn — which
/// is also the cheapest proof that the icon in `Assets.xcassets` compiled and
/// is the one the system will show.
private struct AppIconImage: View {
    @Environment(\.palette) private var palette
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(palette.accent)
            }
        }
        .frame(width: size, height: size)
        // Only iOS: the icon read back out of an iOS bundle is the unmasked
        // square the system rounds off on the Home Screen, and a square one in
        // a panel reads as a screenshot of an icon rather than as an icon.
        // macOS ships the squircle in the artwork, and clipping it again would
        // shave the corners twice.
        .clipShape(.rect(cornerRadius: masksCorners ? size * 0.2237 : 0, style: .continuous))
        .accessibilityHidden(true)
    }

    private var masksCorners: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    private var image: Image? {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        Self.bundled.map(Image.init(uiImage:))
        #endif
    }

    #if os(iOS)
    /// iOS does not answer to the asset catalogue's name for an app icon:
    /// `UIImage(named: "AppIcon")` returns nil, and the compiled icon is
    /// registered under the derived names actool writes into `CFBundleIcons`.
    /// The last of those is the largest. A build with neither falls back to a
    /// plain accent tile rather than to a broken image.
    private static let bundled: UIImage? = {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let names = (primary?["CFBundleIconFiles"] as? [String] ?? []).reversed()
        return names.lazy.compactMap(UIImage.init(named:)).first ?? UIImage(named: "AppIcon")
    }()
    #endif
}

#Preview("About") {
    AboutView(metrics: .desk)
        .environment(\.palette, Palette(theme: ThemePresets.fallback(for: .light)))
}
