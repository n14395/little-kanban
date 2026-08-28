import SwiftUI

/// The priority control. Reuses the design's `PriorityDot` as the swatch, so the
/// picker and the board card read as the same vocabulary — the label is exactly
/// what the design already drew, with a chevron added to say it is editable.
///
/// A menu rather than segments on both surfaces: the inspector's value sits in a
/// two-column grid and the sheet's in a half-width card, and neither has the
/// room for four segments.
///
/// **Least urgent first**, which is `Priority.leastFirst` rather than
/// `allCases` — the one surface that runs the scale upwards. See that property
/// for why the board's own order is the other way round.
struct PriorityPicker: View {
    struct Metrics {
        var font: CGFloat
        var dotDiameter: CGFloat
        var spacing: CGFloat
        /// The square the menu's label claims. A dot and a word are around 17pt
        /// tall, which is a third of what a finger needs.
        var hit: CGFloat

        static let desk = Metrics(font: 12.5, dotDiameter: 7, spacing: 7, hit: 0)
        static let sheet = Metrics(font: 14, dotDiameter: 7, spacing: 6, hit: 44)
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    /// Which task the open session belongs to. A detail surface can be pointed
    /// at another card while the menu is open, and a session ended against the
    /// wrong task would leave the first one's open.
    @State private var editingID: TaskItem.ID?

    var body: some View {
        Menu {
            ForEach(Priority.leastFirst) { option in
                Button {
                    // A menu is one click, so the pick brackets its own session
                    // when the menu's lifecycle did not — `beginSession` is a
                    // no-op if the content's `onAppear` already opened one.
                    beginSession()
                    store.setPriority(option, on: task.id, scope: scope)
                    endSession()
                } label: {
                    // A menu row cannot tint the dot, so the tick carries selection.
                    if option == task.priority {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
            // A `Menu` publishes no open/close callback; its content coming and
            // going is the only signal either platform offers, and macOS sends
            // the appearance once per mounted picker and never the matching
            // disappearance. Hence the bracket in the pick above.
            .onAppear { beginSession() }
            .onDisappear { endSession() }
        } label: {
            HStack(spacing: metrics.spacing) {
                PriorityDot(priority: task.priority, diameter: metrics.dotDiameter)
                Text(task.priority.displayName)
                    .font(palette.ui(metrics.font, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.ink)
                Image(systemName: "chevron.down")
                    .symbolSize(metrics.font - 4, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(palette.inkText(0.35))
            }
            .frame(minWidth: metrics.hit, minHeight: metrics.hit)
            .contentShape(.rect)
        }
        .modifier(BorderlessMenu())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Priority")
        .accessibilityValue(task.priority.displayName)
        // A surface torn down — or re-pointed at another card — with the menu
        // still open would otherwise leave the session open.
        .onChange(of: task.id) { endSession() }
        .onDisappear { endSession() }
    }

    private func beginSession() {
        guard editingID == nil else { return }
        editingID = task.id
        store.beginEditing(.priority, on: task.id, scope: scope)
    }

    private func endSession() {
        guard let editingID else { return }
        store.endEditing(.priority, on: editingID, scope: scope)
        self.editingID = nil
    }
}

/// Strips the menu's own chrome so only the label above shows. On iOS a plain
/// `Menu` already draws nothing; macOS needs saying, and needs saying carefully.
///
/// **`.borderlessButton` does not draw the label it is given.** It bridges to a
/// pull-down button, which keeps the label's *text* and throws the rest away —
/// so the board pill lost its dot and its filled box, the priority menu lost its
/// swatch, and both grew an indicator at the leading edge that
/// `.menuIndicator(.hidden)` does not reach. The panel drew "⌃⌄ Programming"
/// centred where the sheet drew a full-width pill, which is the whole of why the
/// two surfaces did not match.
///
/// `.menuStyle(.button)` renders the label as a button instead — the view as
/// written, laid out by whatever `ButtonStyle` is in the environment — so
/// ``BareButtonStyle`` hands back exactly the HStack the call site built.
///
/// Not private: `BoardDestinationMenu` draws a label of its own and needs the
/// same chrome stripped, and a second copy of a `#if` is a second thing to keep
/// in step.
struct BorderlessMenu: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .menuStyle(.button)
            .buttonStyle(.bare)
        #else
        content
        #endif
    }
}
