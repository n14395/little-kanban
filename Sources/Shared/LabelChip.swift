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
    }

    @Environment(\.palette) private var palette

    let label: LabelDef
    var size: Size = .compact

    var body: some View {
        let tone = palette.resolve(label.tone(for: palette.colorScheme))
        Text(label.name)
            .font(SimpleKanbanFont.ui(size.font, .extraBold, relativeTo: .caption2))
            .tracking(size.font * 0.04)
            .textCase(.uppercase)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(tone.background, in: .rect(cornerRadius: size.radius))
    }
}
