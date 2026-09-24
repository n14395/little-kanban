// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// How a description is drawn, as the four values a platform text view needs.
///
/// A `Font` and a `Color` are SwiftUI's, and the control below is not a SwiftUI
/// control — see ``DescriptionEditor`` for why it cannot be. So the palette is
/// read once, in the wrapper, and what crosses into AppKit and UIKit is this:
/// already resolved, `Equatable`, and therefore something the update pass can
/// compare rather than re-apply on every keystroke.
struct DescriptionStyle: Equatable {
    /// The colour type the two text systems take, named here for the reason
    /// ``LittleKanbanFont/Platform`` is named there: `NSColor` and `UIColor` differ
    /// in nothing this asks of them.
    #if os(macOS)
    typealias Ink = NSColor
    #else
    typealias Ink = UIColor
    #endif

    var font: LittleKanbanFont.Platform
    var textColor: Ink
    var linkColor: Ink
    var lineSpacing: CGFloat

    /// What plain words are drawn in, and what the caret types in. The one place
    /// the paragraph style is built, so the measured height and the drawn text
    /// cannot disagree about the leading.
    var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    /// One line of this face, with its leading. The floor under an empty
    /// description: a text view with nothing in it lays out to no height at all,
    /// and a field you cannot see is a field you cannot click into.
    var lineHeight: CGFloat { font.ascender - font.descender + font.leading + lineSpacing }
}

/// A task's description, with the links in it marked.
///
/// **Why this is a text view and not a `TextField`.** Two of the three things a
/// description now has to do are things a `TextField` cannot be asked:
///
/// - **Follow a link.** A field draws a `String`. Marking a run of it as
///   somewhere to go needs attributed text, which only a text view edits.
/// - **Put the caret where the pointer came down.** Mapping a point to a
///   character is a question about a laid-out line of glyphs, and the only
///   things that can answer it are the text systems — `NSTextView` and
///   `UITextView` both do, and nothing in SwiftUI does.
///
/// **The two states, and what tells them apart.** Not editing, a link carries
/// the `.link` attribute and is underlined, so clicking one opens it and the
/// underline is the app's promise that it will. Editing, the attribute and the
/// underline both go and the accent tint stays: the URL still reads as a URL,
/// but nothing about it says "click me" — because a click there now moves the
/// caret, which is what a click in text you are typing has to do. The rule is
/// one line long and holds everywhere the app draws a link: **underlined means
/// clickable**, which is why a card's preview is tinted and bare too.
///
/// Clicking a word rather than a link hands the description to the caret at
/// that word. Dragging selects instead and stays where it is, so a description
/// can be read and copied without being opened for editing — which the field
/// this replaces could not do at all.
struct DescriptionEditor: View {
    @Environment(\.palette) private var palette

    @Binding var text: String
    /// Whether the caret is in the description. Two-way: the surface sets it to
    /// take the description out of editing — the phone's Done key, the title
    /// field taking focus — and the view sets it when a click puts the caret in
    /// or the keyboard goes down.
    @Binding var isEditing: Bool
    /// The row the description claims when it is shorter than that, so the
    /// finger surfaces keep a target the size of every other control on them.
    /// Zero on the pointer, where a field claims its text and no more.
    var minHeight: CGFloat = 0

    private let size: CGFloat
    private let lineSpacing: CGFloat
    /// What the placeholder is declared relative to, so the hint and the words
    /// that replace it grow by the same amount.
    private let textStyle: Font.TextStyle
    /// The reader's text size applied to `size`. A `Font` carries `relativeTo:`
    /// and grows itself; a platform font is a fixed number of points, so the
    /// growing is done here — through the same `ScaledMetric` the rest of the
    /// app's fixed sizes go through. See ``ChromeScale``.
    @ScaledMetric private var scaledSize: CGFloat

    init(
        text: Binding<String>,
        isEditing: Binding<Bool>,
        size: CGFloat,
        lineSpacing: CGFloat,
        minHeight: CGFloat = 0,
        relativeTo textStyle: Font.TextStyle = .subheadline
    ) {
        _text = text
        _isEditing = isEditing
        self.size = size
        self.lineSpacing = lineSpacing
        self.minHeight = minHeight
        self.textStyle = textStyle
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        DescriptionTextView(text: $text, isEditing: $isEditing, style: style)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .overlay(alignment: .topLeading) { placeholder }
    }

    private var style: DescriptionStyle {
        DescriptionStyle(
            font: palette.uiFont(scaledSize, .medium),
            textColor: DescriptionStyle.Ink(palette.ink(0.62)),
            linkColor: DescriptionStyle.Ink(palette.accent),
            lineSpacing: lineSpacing
        )
    }

    /// What the field used to get from the system for free. Drawn rather than
    /// asked for because the two text views do not agree that they have one:
    /// `NSTextView` takes a placeholder string and `UITextView` has no such
    /// thing, and a prompt that appeared on one platform only is worse than one
    /// the app draws itself on both.
    ///
    /// Below the ink floor on purpose. A placeholder is a hint at what to type
    /// rather than something to read — it is gone the moment there is anything
    /// to say — and at the floor it reads as a description somebody wrote.
    @ViewBuilder private var placeholder: some View {
        if text.isEmpty {
            Text("Add a description", comment: "Placeholder in the empty description field")
                .font(palette.ui(size, .medium, relativeTo: textStyle))
                .foregroundStyle(palette.ink(0.4))
                .allowsHitTesting(false)
        }
    }
}

/// `text` with its links marked, in the two dresses ``DescriptionEditor``
/// describes. `isLive` is the whole difference: it adds the attribute that makes
/// a click open the URL, and the underline that says so.
private func styledDescription(
    _ text: String, style: DescriptionStyle, isLive: Bool
) -> NSAttributedString {
    let out = NSMutableAttributedString(string: text, attributes: style.base)
    for match in TaskLinks.matches(in: text) {
        let range = NSRange(match.range, in: text)
        out.addAttribute(.foregroundColor, value: style.linkColor, range: range)
        guard isLive else { continue }
        out.addAttribute(.link, value: match.url, range: range)
        out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        out.addAttribute(.underlineColor, value: style.linkColor, range: range)
    }
    return out
}

/// Re-marks what is already there, without touching a character of it.
///
/// The path a keystroke takes. Replacing the storage would work and would also
/// drop the selection on the floor — every letter typed would send the caret to
/// the end — so this sets attributes over the text that is already laid out,
/// which leaves the selection alone because nothing about the characters moved.
/// It is what keeps a URL lighting up as the last letter of it is typed.
private func rehighlight(_ storage: NSTextStorage, style: DescriptionStyle, isLive: Bool) {
    let text = storage.string
    let whole = NSRange(location: 0, length: (text as NSString).length)
    storage.beginEditing()
    storage.setAttributes(style.base, range: whole)
    for match in TaskLinks.matches(in: text) {
        let range = NSRange(match.range, in: text)
        storage.addAttribute(.foregroundColor, value: style.linkColor, range: range)
        guard isLive else { continue }
        storage.addAttribute(.link, value: match.url, range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.addAttribute(.underlineColor, value: style.linkColor, range: range)
    }
    storage.endEditing()
}

// MARK: - The pointer

#if os(macOS)

private struct DescriptionTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let style: DescriptionStyle

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Built on a TextKit 1 stack, deliberately.
    ///
    /// A programmatically created `NSTextView` is TextKit 2, whose layout is
    /// asked for through a different set of objects than `UITextView`'s — and
    /// the one thing this view has to do on both platforms, measure its own
    /// height, would then be written twice against two APIs. Handing it a
    /// container built here pins the stack, and `UITextView(usingTextLayoutManager:)`
    /// pins the same one on the phone.
    func makeNSView(context: Context) -> DescriptionNSTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer()
        container.size = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let view = DescriptionNSTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.isRichText = false
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        // The app finds its own links — see ``TaskLinks``, which refuses the
        // schemes this would happily mark. Left on, AppKit writes `.link`
        // attributes of its own into the storage and the two sets fight.
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        // A description is where URLs live, and both of these corrupt one
        // silently: a hyphen in a path becomes an en dash, a quote in a query
        // string becomes a curly quote, and the link stops resolving.
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.setAccessibilityLabel(
            String(localized: "Description", comment: "Accessibility label for a task's description")
        )
        view.beginEditing = { [weak view] (index: Int) in
            guard let view else { return }
            context.coordinator.beginEditing(view, at: index)
        }
        return view
    }

    func updateNSView(_ view: DescriptionNSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(view, text: text, isEditing: isEditing, style: style)
    }

    /// The height the text wants at the width it has been offered. Without this
    /// the view is laid out at whatever `NSTextView` claims for itself, which is
    /// a single line: a three-line description drew one line and hid the rest.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: DescriptionNSTextView, context: Context
    ) -> CGSize? {
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else {
            return nil
        }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        return CGSize(width: width, height: ceil(max(used, style.lineHeight)))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DescriptionTextView
        /// What the view was last dressed in, so a pass that changed neither the
        /// words nor the theme does not rebuild the storage under the caret.
        private var applied: DescriptionStyle?
        private var appliedLive: Bool?
        private var isWriting = false

        init(_ parent: DescriptionTextView) { self.parent = parent }

        /// Brings the view up to date with the state SwiftUI holds. The order
        /// matters: `isEditable` decides which dress the text wears, so it is
        /// settled before anything is drawn in it.
        func sync(
            _ view: DescriptionNSTextView, text: String, isEditing: Bool, style: DescriptionStyle
        ) {
            let wasEditable = view.isEditable
            view.isEditable = isEditing
            view.linkTextAttributes = [
                .foregroundColor: style.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand,
            ]
            let isLive = !isEditing
            let hasNewText = view.string != text
            let hasNewDress = applied != style || appliedLive != isLive
            if hasNewText || hasNewDress {
                let selection = view.selectedRange()
                if hasNewText {
                    view.textStorage?.setAttributedString(
                        styledDescription(text, style: style, isLive: isLive)
                    )
                } else if let storage = view.textStorage {
                    rehighlight(storage, style: style, isLive: isLive)
                    view.setSelectedRange(selection)
                }
                applied = style
                appliedLive = isLive
            }
            view.typingAttributes = style.base

            // Focus follows the binding, so a description opened by anything
            // other than a click on it still lands where it says it does.
            //
            // **Given up only on the way out of editing**, which `wasEditable`
            // is the whole of. A selectable text view takes first responder to
            // hold a selection as well as a caret, so a pass that resigned
            // whenever `isEditing` was false would take the selection off a
            // description somebody was dragging across to copy — and every
            // unrelated redraw of the panel is such a pass.
            let isFirstResponder = view.window?.firstResponder === view
            if isEditing, !isFirstResponder {
                view.window?.makeFirstResponder(view)
            } else if !isEditing, wasEditable, isFirstResponder {
                view.window?.makeFirstResponder(nil)
            }
        }

        /// A click on a word: the caret goes where the pointer came down, and
        /// the description becomes editable under it.
        func beginEditing(_ view: DescriptionNSTextView, at index: Int) {
            guard !view.isEditable else { return }
            view.isEditable = true
            if let storage = view.textStorage {
                rehighlight(storage, style: parent.style, isLive: false)
                appliedLive = false
            }
            view.window?.makeFirstResponder(view)
            let length = (view.string as NSString).length
            view.setSelectedRange(NSRange(location: min(index, length), length: 0))
            parent.isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? DescriptionNSTextView, !isWriting else { return }
            isWriting = true
            defer { isWriting = false }
            parent.text = view.string
            if let storage = view.textStorage {
                rehighlight(storage, style: parent.style, isLive: false)
            }
            view.typingAttributes = parent.style.base
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? DescriptionNSTextView else { return }
            view.isEditable = false
            parent.isEditing = false
        }
    }
}

/// The text view itself, which exists for one method.
///
/// A click has to be told apart from a drag before it can mean "put the caret
/// here", and the only place that is knowable is around `super.mouseDown` —
/// which does not return until the mouse comes back up, so what it leaves in the
/// selection is the answer. An empty selection is a click; anything else is a
/// drag that selected text, and a drag is the user reading rather than editing.
final class DescriptionNSTextView: NSTextView {
    /// Called with the character the pointer came down on. Set by the
    /// representable; the view holds no opinion about what editing means.
    var beginEditing: ((Int) -> Void)?

    /// Whether the click that is being handled landed on a link. AppKit answers
    /// this by calling ``clicked(onLink:at:)`` from inside `mouseDown`, which
    /// is why the flag is read after `super` rather than before it.
    private var didClickLink = false

    override func clicked(onLink link: Any, at charIndex: Int) {
        didClickLink = true
        super.clicked(onLink: link, at: charIndex)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isEditable else {
            super.mouseDown(with: event)
            return
        }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        didClickLink = false
        super.mouseDown(with: event)
        guard !didClickLink, selectedRange().length == 0 else { return }
        beginEditing?(index)
    }
}

#endif

// MARK: - The finger

#if os(iOS)

private struct DescriptionTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let style: DescriptionStyle

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1, for the reason the Mac's stack is built by hand: one
        // measuring path rather than two.
        let view = UITextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        // The sheet is the scroller. A text view that scrolled inside it would
        // trap the drag and cap the description at its own height.
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // The app finds its own links — see ``TaskLinks``.
        view.dataDetectorTypes = []
        // Both of these rewrite a URL as it is typed: a hyphen becomes an en
        // dash, a quote in a query string becomes a curly one.
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.accessibilityLabel =
            String(localized: "Description", comment: "Accessibility label for a task's description")

        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:))
        )
        // Beside the text view's own tap handling rather than instead of it: a
        // tap on a link is the text view's to answer, and this one stands down
        // when it sees one.
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(view, text: text, isEditing: isEditing, style: style)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: UITextView, context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(max(fitted.height, style.lineHeight)))
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DescriptionTextView
        private var applied: DescriptionStyle?
        private var appliedLive: Bool?
        private var isWriting = false

        init(_ parent: DescriptionTextView) { self.parent = parent }

        func sync(_ view: UITextView, text: String, isEditing: Bool, style: DescriptionStyle) {
            let wasEditable = view.isEditable
            view.isEditable = isEditing
            view.linkTextAttributes = [
                .foregroundColor: style.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            let isLive = !isEditing
            let hasNewText = view.text != text
            let hasNewDress = applied != style || appliedLive != isLive
            if hasNewText || hasNewDress {
                let selection = view.selectedRange
                if hasNewText {
                    view.attributedText = styledDescription(text, style: style, isLive: isLive)
                } else {
                    rehighlight(view.textStorage, style: style, isLive: isLive)
                    view.selectedRange = selection
                }
                applied = style
                appliedLive = isLive
            }
            view.typingAttributes = style.base

            // Resigned only on the way out of editing — see the Mac's `sync`,
            // which says why a text view holding a selection must not be
            // stripped of first responder by a redraw.
            if isEditing, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !isEditing, wasEditable, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }

        /// A tap on a word rather than on a link: the caret goes where the
        /// finger came down. A tap on a link is left alone — the text view opens
        /// it, which is what the `.link` attribute is there for.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView, !view.isEditable else { return }
            let point = gesture.location(in: view)
            guard !isOnLink(point, in: view) else { return }
            view.isEditable = true
            rehighlight(view.textStorage, style: parent.style, isLive: false)
            appliedLive = false
            view.becomeFirstResponder()
            view.selectedRange = NSRange(location: characterIndex(point, in: view), length: 0)
            parent.isEditing = true
        }

        /// Which character the finger came down on. `closestPosition` rather
        /// than a hit test, so a tap past the end of a line lands the caret at
        /// the end of it rather than nowhere.
        private func characterIndex(_ point: CGPoint, in view: UITextView) -> Int {
            guard let position = view.closestPosition(to: point) else { return 0 }
            return view.offset(from: view.beginningOfDocument, to: position)
        }

        /// Whether there is a link under the point — *under* it, not near it.
        /// `characterRange(at:)` answers with the nearest range rather than the
        /// containing one, so a tap in the blank space after a line ending in a
        /// URL would otherwise read as a tap on that URL.
        private func isOnLink(_ point: CGPoint, in view: UITextView) -> Bool {
            guard let range = view.characterRange(at: point),
                  view.firstRect(for: range).contains(point)
            else { return false }
            let index = view.offset(from: view.beginningOfDocument, to: range.start)
            guard index < view.textStorage.length else { return false }
            return view.textStorage.attribute(.link, at: index, effectiveRange: nil) != nil
        }

        func textViewDidChange(_ view: UITextView) {
            guard !isWriting else { return }
            isWriting = true
            defer { isWriting = false }
            parent.text = view.text
            rehighlight(view.textStorage, style: parent.style, isLive: false)
            view.typingAttributes = parent.style.base
        }

        func textViewDidEndEditing(_ view: UITextView) {
            view.isEditable = false
            parent.isEditing = false
        }
    }
}

#endif
