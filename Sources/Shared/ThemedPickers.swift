// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The three system controls this app had left, drawn by hand instead.
///
/// **Why they had to go.** `.tint(palette.accent)` reaches a `Toggle`'s switch
/// and a popup button's chevron block, and it reaches nothing else. A
/// `.borderedProminent` button picks its own label colour and wears a focus ring
/// in `NSColor.keyboardFocusIndicatorColor`; a `.segmented` picker marks the
/// chosen segment in `NSColor.controlAccentColor`; a `Stepper` draws a bezel in
/// the system's control grey; and the macOS `TabView`'s tab bar marks the chosen
/// tab in both of those at once. None of the four follows a tint, and all four
/// follow the *system* accent — so a board wearing Aurora's mint showed a rust
/// ring around Done and a rust "Data" tab, because rust is what the machine's
/// own accent happened to be that afternoon.
///
/// So these three carry the vocabulary the rest of the app already draws with:
/// ``BorderlessMenu`` over a label the call site owns, ``MoveToPicker``'s track
/// and floating pill, and `palette.ink(0.06)` under anything field-shaped. A
/// menu's *rows* are still the system's — a menu row cannot be tinted on either
/// platform, which is why every menu in this app marks its current row with a
/// tick rather than a colour.

/// One thing a picker or a segmented control offers.
///
/// Carried as a value rather than built from a `ForEach` of tags so that a
/// control can be handed options gathered from several places at once — the
/// quick-add destination is the Inbox and then every column of every board —
/// and so the drawn label is a plain lookup rather than a view hierarchy that
/// has to be searched for the selected tag.
struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    /// The heading this option is filed under in a menu, or `nil` for one that
    /// stands on its own. Consecutive options naming the same section are drawn
    /// under one heading; a `nil` between two of them closes the group.
    var section: String?

    init(_ value: Value, _ title: String, section: String? = nil) {
        self.value = value
        self.title = title
        self.section = section
    }

    var id: Value { value }
}

/// A value chosen from a menu: the design's `choice` row, as a control.
///
/// The drawn label is the current title and a chevron on `ink(0.06)` — the same
/// ground the text fields beside it stand on, so a row of "field, condition,
/// value" reads as one row of controls rather than as two system popups and a
/// field. `nil` selection, or a selection no longer in `options` — a criterion
/// naming a board since deleted — draws ``placeholder`` rather than blank, which
/// is what an `NSPopUpButton` does with an unmatched tag and is how a stale rule
/// used to re-point itself at whatever happened to be first.
struct ThemedPicker<Value: Hashable>: View {
    @Environment(\.palette) private var palette

    let options: [ChoiceOption<Value>]
    @Binding var selection: Value
    /// What VoiceOver calls the control. The drawn label is the *value*, so
    /// without this the control would read out as its own answer.
    let name: String
    var placeholder = "—"
    var font: CGFloat = 12.5
    /// What the control draws. The pill keeps this height whatever the hit area
    /// around it claims — see ``hit``.
    var height: CGFloat = 26
    /// What it claims for touch, over and above what it draws. Zero at a
    /// pointer, 44 under a finger; the same bargain every other control in the
    /// app makes.
    var hit: CGFloat = 0
    var radius: CGFloat = 6

    var body: some View {
        Menu {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if let heading = group.heading {
                    Section(heading) { rows(group.options) }
                } else {
                    rows(group.options)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(currentTitle)
                    .font(palette.ui(font, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .symbolSize(font - 4, weight: .bold, relativeTo: .caption2)
                    .foregroundStyle(palette.inkText(0.35))
            }
            .padding(.horizontal, 8)
            .frame(minHeight: height)
            .background(palette.ink(0.06), in: .rect(cornerRadius: radius))
            .frame(minHeight: hit)
            .contentShape(.rect)
        }
        .modifier(BorderlessMenu())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(name)
        .accessibilityValue(currentTitle)
    }

    @ViewBuilder private func rows(_ options: [ChoiceOption<Value>]) -> some View {
        ForEach(options) { option in
            Button {
                selection = option.value
            } label: {
                // A tick rather than a tint, for `PriorityPicker`'s reason: a
                // menu row cannot colour anything on either platform.
                if option.value == selection {
                    Label(option.title, systemImage: "checkmark")
                } else {
                    Text(option.title)
                }
            }
        }
    }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? placeholder
    }

    /// The options cut into runs sharing a heading, in the order they were
    /// given. A run rather than a grouping by name so the caller decides the
    /// order of both the headings and what is under them — `Dictionary` would
    /// decide neither.
    private var groups: [(heading: String?, options: [ChoiceOption<Value>])] {
        var groups: [(heading: String?, options: [ChoiceOption<Value>])] = []
        for option in options {
            if let last = groups.last, last.heading == option.section {
                groups[groups.count - 1].options.append(option)
            } else {
                groups.append((option.section, [option]))
            }
        }
        return groups
    }
}

/// A value chosen from two or three segments side by side, for the places where
/// they fit and reading the alternatives without opening anything is worth the
/// width: the theme editor's light-or-dark slot.
///
/// The same track and floating pill ``MoveToPicker`` draws — one vocabulary for
/// "one of these, and here is which" rather than a second one that happens to
/// look like the system's.
struct ThemedSegments<Value: Hashable>: View {
    @Environment(\.palette) private var palette

    let options: [ChoiceOption<Value>]
    @Binding var selection: Value
    /// VoiceOver's name for the control. Each segment reads out as a button with
    /// the selected trait, the way the rest of the app's chip rows do.
    let name: String
    var font: CGFloat = 12
    var height: CGFloat = 24
    var hit: CGFloat = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let isCurrent = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(palette.ui(font, .bold, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? palette.ink : palette.inkText(0.5))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: height)
                        .background {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isCurrent ? palette.card : .clear)
                                .shadow(color: isCurrent ? palette.shadow(0.16) : .clear, radius: 1.5, y: 1)
                        }
                        .frame(minHeight: hit)
                }
                .bareButton()
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(palette.ink(0.06), in: .rect(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }
}

/// A number nudged up and down: `Stepper` without the system bezel.
///
/// Holding is not offered, and the native control's repeat-on-hold is the one
/// thing lost here. Every use in the app spans a couple of dozen steps at most —
/// an interval of 1…99, a cap of 1…200, a WIP limit — and all three sit beside a
/// field the number can also be typed into.
struct ThemedStepper<Label: View>: View {
    @Environment(\.palette) private var palette

    @Binding var value: Int
    let range: ClosedRange<Int>
    /// VoiceOver's name, and the adjustable value it reads after it. The drawn
    /// label is the caller's sentence — "Every 2", "At most 20" — which reads
    /// out on its own as text, so the control states its own name rather than
    /// borrowing one.
    let name: String
    var step = 1
    var hit: CGFloat = 0
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: 8) {
            label()
            HStack(spacing: 0) {
                button("minus", by: -step, enabled: value > range.lowerBound)
                Rectangle()
                    .fill(palette.ink(0.08))
                    .frame(width: 1, height: 14)
                button("plus", by: step, enabled: value < range.upperBound)
            }
            .background(palette.ink(0.06), in: .rect(cornerRadius: 6))
            .frame(minHeight: hit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(step)
            case .decrement: nudge(-step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, by delta: Int, enabled: Bool) -> some View {
        Button { nudge(delta) } label: {
            Image(systemName: symbol)
                .symbolSize(9, weight: .bold, relativeTo: .caption2)
                .foregroundStyle(palette.inkText(enabled ? 0.6 : 0.25))
                .frame(width: 22, height: 24)
                .contentShape(.rect)
        }
        .bareButton()
        .disabled(!enabled)
        .accessibilityHidden(true)
    }

    private func nudge(_ delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}
