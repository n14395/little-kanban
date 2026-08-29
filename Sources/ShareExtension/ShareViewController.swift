import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
// Not `private`: the principal class below inherits from `ShareHost`, and a
// class may not be more visible than its superclass.
typealias ShareHost = NSViewController
typealias ShareHosting = NSHostingController
#else
import UIKit
typealias ShareHost = UIViewController
typealias ShareHosting = UIHostingController
#endif

/// The share extension's principal class, named in `Resources/ShareInfo.plist`
/// as `$(PRODUCT_MODULE_NAME).ShareViewController`.
///
/// One class for both platforms, because the only thing that differs is which
/// framework's view controller it inherits from and which hosting controller
/// puts the SwiftUI in it. Everything with a decision in it — what the payload
/// becomes, what the sheet says, where it is written — is shared.
///
/// **It reads the share and writes a file. That is all it does.** No board
/// file, no SwiftData store, no CloudKit: see ``CaptureInbox`` for why, at
/// length. The app drains the folder on its next foreground —
/// ``BoardStore/adoptPendingCaptures()``.
final class ShareViewController: ShareHost {
    override func viewDidLoad() {
        super.viewDidLoad()
        // The payload arrives through `NSItemProvider`, which is asynchronous
        // whatever the type. The sheet cannot be built until the draft exists,
        // so the controller comes up empty for the moment that takes — wearing
        // the ground colour rather than flashing white.
        Task { await present() }
    }

    @MainActor
    private func present() async {
        let draft = await draft()
        let root = ShareRoot(
            draft: draft,
            add: { [weak self] title in self?.add(draft, titled: title) ?? nil },
            cancel: { [weak self] in self?.cancel() }
        )
        let hosting = ShareHosting(rootView: root)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #if os(iOS)
        hosting.didMove(toParent: self)
        #endif
    }

    /// Writes the capture and closes the sheet, or returns the sentence saying
    /// why it could not.
    ///
    /// **The sheet stays open on failure**, with the user's text still in it.
    /// There is nowhere here to retry to and nothing to queue — the container is
    /// the queue — so the only useful thing left is to not pretend it worked.
    @MainActor
    private func add(_ draft: PendingCapture, titled title: String) -> String? {
        var capture = draft
        capture.title = title
        do {
            try CaptureInbox.write(capture)
        } catch CaptureInbox.WriteError.noContainer {
            return String(localized: "This copy of Simple Kanban is not set up for sharing.",
                          comment: "Share sheet error when the build is not entitled to the App Group")
        } catch {
            return String(localized: "That could not be saved. Try again, or add it in Simple Kanban.",
                          comment: "Share sheet error when the capture could not be written to disk")
        }
        extensionContext?.completeRequest(returningItems: [])
        return nil
    }

    @MainActor
    private func cancel() {
        // `cancelRequest` rather than `completeRequest`: the host app is told
        // the share was declined, which is what lets Safari leave its own sheet
        // as it was rather than reporting a success nobody asked for.
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }

    /// What was shared, as a draft card.
    ///
    /// Two sources, in the order they are trusted. `attributedContentText` is
    /// what a browser sends as the page's name and what a selection share sends
    /// as the selection, and it is on the item rather than in an attachment; the
    /// attachments carry the URL, and the plain text for hosts that put it
    /// there instead. First one of each wins — a share of several things is
    /// still one card, because the Inbox is for the thing you were looking at.
    @MainActor
    private func draft() async -> PendingCapture {
        var text: String?
        var url: URL?

        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            if text == nil, let shared = item.attributedContentText?.string, !shared.isEmpty {
                text = shared
            }
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    url = await Self.loadURL(from: provider)
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    text = await Self.loadText(from: provider)
                }
            }
        }
        return CaptureDraft.from(text: text, url: url)
    }

    /// The callback API rather than `loadItem`'s `async` spelling, deliberately:
    /// that one hands back an `NSSecureCoding`, which is not `Sendable` and
    /// cannot cross back to this actor under Swift 6. Converting inside the
    /// callback and resuming with the value — a `URL`, a `String` — sidesteps
    /// the whole question.
    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }
}

/// Resolves the palette and hands it to the sheet — the extension's much
/// smaller `RootView`.
///
/// The theme comes out of the widgets' digest, which is already in the App
/// Group: no board is opened to get it. With no digest yet — a fresh install
/// that has not run the app — it falls back to the shipping pair, which is what
/// a widget draws in the same position.
private struct ShareRoot: View {
    @Environment(\.colorScheme) private var colorScheme

    let draft: PendingCapture
    var add: (String) -> String?
    var cancel: () -> Void

    var body: some View {
        let digest = WidgetDigestFile.read()
        let themes = digest?.themes ?? .seed
        let override = digest?.appearance ?? .system
        let palette = Palette(theme: themes.theme(for: (override.colorScheme ?? colorScheme).themeAppearance))

        CaptureSheet(draft: draft, add: add, cancel: cancel)
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .preferredColorScheme(override.colorScheme)
    }
}
