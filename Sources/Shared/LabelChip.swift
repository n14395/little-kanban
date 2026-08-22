import SwiftUI

/// The uppercase pill used for task labels.
struct LabelChip: View {
    enum Size {
        /// macOS cards and inspector.
        case compact
        /// iOS sheet, where touch targets and type run larger.
        case comfortable

        var font: CGFloat { self == .compact ? 10 : 11 }
        var horizontalPadding: CGFloat { self == .compact ? 7 : 9 }
        var verticalPadding: CGFloat { self == .compact ? 3 : 5 }
        var radius: CGFloat { self == .compact ? 6 : 8 }
        /// The `×` an applied chip carries.
        var removeGlyph: CGFloat { self == .compact ? 8 : 9.5 }
        var removeSpacing: CGFloat { self == .compact ? 5 : 6 }
        /// Where a user-created name starts truncating. Without a ceiling one
        /// long label takes a whole `FlowLayout` line to itself and pushes the
        /// rest of the row down. Scaled at the call site: the ceiling is a
        /// width around type, so it has to grow with the type.
        var maxNameWidth: CGFloat { self == .compact ? 132 : 168 }
        /// The other half of that ceiling: the width alone only clips, so the
        /// name has to be held to one line and told where to break. Named here
        /// rather than written into the body because a rendering modifier is
        /// invisible to the suite, and a constant is not.
        var nameLineLimit: Int { 1 }
        var nameTruncation: Text.TruncationMode { .tail }

        /// Whether the inline remove control is drawn at all. The pointer
        /// surface reveals it on hover; the touch surface carries the same
        /// action on a long press, so it reserves no room for a control it
        /// would never show.
        var revealsRemoveOnHover: Bool { self == .compact }
    }

    @Environment(\.palette) private var palette
    @State private var isHovering = false
    private var chrome = ChromeScale()

    let label: LabelDef
    var size: Size = .compact
    /// Takes the label off the task. Nil on a card, where the chip is a read-out
    /// and not a control, and the chip then renders exactly as it always has.
    var onRemove: (() -> Void)?

    var body: some View {
        let tone = palette.resolve(label.tone(for: palette.colorScheme))
        HStack(spacing: size.removeSpacing) {
            Text(label.name)
                .font(SimpleKanbanFont.ui(size.font, .extraBold, relativeTo: .caption2))
                // Kerning rather than tracking: tracking adds its space after
                // the *last* glyph too, and the frame is measured without it,
                // so "DESIGN" was reported clipped inside a 40pt chip it needed
                // 43 for. Kerning only spaces the letters against each other.
                .kerning(size.font * 0.04)
                .textCase(.uppercase)
                .lineLimit(size.nameLineLimit)
                .truncationMode(size.nameTruncation)
                .frame(maxWidth: chrome(size.maxNameWidth, cap: 2), alignment: .leading)

            if let onRemove, size.revealsRemoveOnHover {
                // The slot is held open whether or not the pointer is here: a
                // chip that grew on hover would reflow the row out from under
                // the pointer that was aiming at it.
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(SimpleKanbanFont.ui(size.removeGlyph, .extraBold, relativeTo: .caption2))
                        .fontWeight(.bold)
                }
                .buttonStyle(.bare)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .accessibilityHidden(!isHovering)
                .accessibilityLabel("Remove label")
            }
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(tone.background, in: .rect(cornerRadius: size.radius))
        .onHover { isHovering = $0 }
        .modifier(RemoveMenu(onRemove: onRemove))
    }
}

/// The remove action as a long-press (touch) or right-click (pointer) menu —
/// the only path VoiceOver has to a control that otherwise waits for a hover.
private struct RemoveMenu: ViewModifier {
    let onRemove: (() -> Void)?

    func body(content: Content) -> some View {
        if let onRemove {
            content.contextMenu {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove Label", systemImage: "xmark")
                }
            }
        } else {
            content
        }
    }
}
