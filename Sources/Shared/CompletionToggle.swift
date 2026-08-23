import SwiftUI

/// The tick control, shared by the board cards and the checklist rows so the two
/// cannot drift into two different ideas of what "done" looks like: accent fill,
/// accent border, white glyph, nothing else.
///
/// The shape's radius is a metric rather than a constant — a card wants the
/// circle the spec draws beside a title, a checklist row wants the design's
/// rounded square — but the rest of the vocabulary is fixed here.
struct CompletionToggle: View {
    struct Metrics {
        /// The drawn box.
        var size: CGFloat
        var radius: CGFloat
        var borderWidth: CGFloat
        /// The tick, as a fraction of `size`.
        var glyphScale: CGFloat
        /// The square the button actually claims, which is larger than the box
        /// on touch, where the drawn size is well under the 44pt minimum.
        var hitSize: CGFloat

        /// A card on macOS.
        static let desk = Metrics(size: 16, radius: 8, borderWidth: 1.5, glyphScale: 0.56, hitSize: 26)
        /// A card on iOS.
        static let sheet = Metrics(size: 22, radius: 11, borderWidth: 1.75, glyphScale: 0.55, hitSize: 44)
        /// A checklist row on macOS.
        static let deskRow = Metrics(size: 15, radius: 5, borderWidth: 1.5, glyphScale: 0.58, hitSize: 18)
        /// A checklist row on iOS.
        static let sheetRow = Metrics(size: 20, radius: 6, borderWidth: 1.5, glyphScale: 0.58, hitSize: 44)
        // There were two more — `deskPanel` and `sheetPanel`, sized to stand
        // beside the detail surfaces' serif title. The tick they were for is
        // gone from both, and they go with the case rather than being left
        // behind as presets nothing can ask for.
    }

    @Environment(\.palette) private var palette

    let isDone: Bool
    var metrics: Metrics = .desk
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            box.frame(minWidth: metrics.hitSize, minHeight: metrics.hitSize)
        }
        .buttonStyle(.bare)
        // The label says what the tap does, because that is what VoiceOver
        // reads for a button; the trait carries the current state.
        .accessibilityLabel(isDone ? Text("Mark as not done") : Text("Mark as done"))
        .accessibilityAddTraits(isDone ? [.isSelected] : [])
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: metrics.radius)
            .fill(isDone ? palette.accent : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius)
                    .strokeBorder(
                        isDone ? palette.accent : palette.ink(0.25),
                        lineWidth: metrics.borderWidth
                    )
            }
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(SimpleKanbanFont.ui(
                            metrics.size * metrics.glyphScale, .bold, relativeTo: .caption2
                        ))
                        .fontWeight(.bold)
                        .foregroundStyle(palette.onAccent)
                }
            }
            .frame(width: metrics.size, height: metrics.size)
    }
}
