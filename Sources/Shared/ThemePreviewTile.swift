import SwiftUI

/// A theme, shown as a small picture of the app wearing it.
///
/// **Every parameter is in here somewhere**, which is the point: a swatch row
/// would show the colours and tell you nothing about what the theme *is*. The
/// ground carries the gradient at its real angle, the strip down the left is the
/// panel overlay over it, the title is the display face at the weight and slant
/// the theme sets, the card is the card fill at the card radius inside the card
/// border, the chips are the label rule and the due chips, and the pill is the
/// highlight with its own on-accent text.
///
/// It draws from a ``Palette`` built on the theme it is given rather than the
/// one in the environment — this is a picture of a theme that is *not* in force,
/// and a preview that borrowed the current one would show every tile alike.
struct ThemePreviewTile: View {
    let theme: Theme
    /// 1 is the size the tile is drawn at in the picker; the editor's preview
    /// asks for more. Everything below is a multiple of it, so there is one
    /// number to change and no second set of metrics to keep in agreement.
    var scale: CGFloat = 1

    private var palette: Palette { Palette(theme: theme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            board
        }
        .frame(width: 248 * scale, height: 152 * scale)
        .background(palette.windowFill)
        .clipShape(.rect(cornerRadius: 10 * scale))
        // Its own hairline rather than the theme's: this is the edge of a
        // *picture*, and a theme whose card border is nearly invisible would
        // otherwise have no tile edge either.
        .overlay {
            RoundedRectangle(cornerRadius: 10 * scale)
                .strokeBorder(palette.ink(0.12), lineWidth: 1)
        }
        // The tile is one thing to a reader — the name and the state are said by
        // the row around it, and a screen reader walking eleven coloured
        // rectangles is not being told anything.
        .accessibilityHidden(true)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            label(Sample.boards)
            boardRow(dot: palette.accent, name: Sample.personal, isActive: true)
            boardRow(dot: palette.theme.status.done.color, name: Sample.errands, isActive: false)
            boardRow(dot: palette.theme.status.medium.color, name: Sample.reading, isActive: false)
            Spacer(minLength: 0)
            Circle()
                .fill(palette.accent)
                .frame(width: 16 * scale, height: 16 * scale)
                .overlay {
                    Image(systemName: "plus")
                        .font(palette.ui(9 * scale, .bold))
                        .foregroundStyle(palette.onAccent)
                }
        }
        .padding(8 * scale)
        .frame(width: 74 * scale, alignment: .leading)
        .background(palette.panelOverlay)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 5 * scale) {
                Text(verbatim: theme.name)
                    .font(palette.display(13 * scale))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // The wash, which has no other home in a picture this size.
                Text(Sample.search)
                    .font(palette.ui(6.5 * scale, .semibold))
                    .foregroundStyle(palette.inkText(theme.ink.faint))
                    .padding(.horizontal, 5 * scale)
                    .padding(.vertical, 2.5 * scale)
                    .background(palette.wash, in: .capsule)
            }
            card(isSelected: false)
            card(isSelected: true)
            Spacer(minLength: 0)
        }
        .padding(8 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(isSelected: Bool) -> some View {
        let chip = palette.chipTone(for: .hex(isSelected ? theme.status.done.hex : theme.highlight.accent.hex))
        let due = isSelected
            ? palette.dueTone(urgency: .soon, isDone: false)
            : palette.dueTone(urgency: .overdue, isDone: false)
        return VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(spacing: 4 * scale) {
                Text(isSelected ? Sample.home : Sample.errand)
                    .font(palette.ui(5.5 * scale, .extraBold))
                    .kerning(0.25 * scale)
                    .foregroundStyle(chip.foreground)
                    .padding(.horizontal, 4 * scale)
                    .padding(.vertical, 1.5 * scale)
                    .background(chip.background, in: .rect(cornerRadius: 3 * scale))
                Spacer(minLength: 0)
                Circle()
                    .fill(palette.priorityColor(.max))
                    .frame(width: 4 * scale, height: 4 * scale)
            }
            Text(isSelected ? Sample.hallway : Sample.dentist)
                .font(palette.ui(7.5 * scale, .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            HStack(spacing: 4 * scale) {
                Text(isSelected ? Sample.friday : Sample.today)
                    .font(palette.ui(6 * scale, .bold))
                    .foregroundStyle(due.foreground)
                    .padding(.horizontal, 4 * scale)
                    .padding(.vertical, 1.5 * scale)
                    .background(due.background, in: .rect(cornerRadius: 3 * scale))
                Spacer(minLength: 0)
                Text(verbatim: "\(Sample.subtasksDone)/\(Sample.subtasks)")
                    .font(palette.ui(6 * scale, .bold))
                    .foregroundStyle(palette.inkText(theme.ink.faint))
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 5 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: .rect(cornerRadius: theme.card.radius * scale * 0.72))
        .overlay {
            RoundedRectangle(cornerRadius: theme.card.radius * scale * 0.72)
                .strokeBorder(
                    isSelected ? palette.accent : palette.cardBorder,
                    lineWidth: isSelected ? 1.4 * scale : 1
                )
        }
    }

    private func boardRow(dot: Color, name: String, isActive: Bool) -> some View {
        HStack(spacing: 4 * scale) {
            Circle().fill(dot).frame(width: 4 * scale, height: 4 * scale)
            Text(verbatim: name)
                .font(palette.ui(6.5 * scale, isActive ? .extraBold : .semibold))
                .foregroundStyle(isActive ? palette.accent : palette.inkText(theme.ink.muted))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4 * scale)
        .padding(.vertical, 2.5 * scale)
        .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: 4 * scale))
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(palette.ui(5.5 * scale, .extraBold))
            .kerning(0.6 * scale)
            .foregroundStyle(palette.inkText(theme.ink.faint))
            .padding(.horizontal, 4 * scale)
    }
}

/// The words in the picture.
///
/// Translated like anything else on screen. A preview of the app should read as
/// the app does, and somebody comparing twenty tiles in French should not have
/// to read English to do it — the tile is decoration, but it is decoration made
/// of sentences.
private enum Sample {
    static let boards = String(localized: "Boards", comment: "Sidebar heading in the theme preview")
    static let personal = String(localized: "Personal", comment: "Sample board name in the theme preview")
    static let errands = String(localized: "Errands", comment: "Sample board name in the theme preview")
    static let reading = String(localized: "Reading", comment: "Sample board name in the theme preview")
    static let search = String(localized: "Search", comment: "Sample search field in the theme preview")
    static let home = String(localized: "HOME", comment: "Sample uppercase label chip in the theme preview")
    static let errand = String(localized: "ERRAND", comment: "Sample uppercase label chip in the theme preview")
    static let hallway = String(localized: "Repaint the hallway", comment: "Sample task title in the theme preview")
    static let dentist = String(localized: "Book the dentist", comment: "Sample task title in the theme preview")
    static let friday = String(localized: "Fri", comment: "Sample due-date chip in the theme preview")
    static let today = String(localized: "Today", comment: "Sample overdue chip in the theme preview")
    /// A count rather than a phrase, so it is the same in every language.
    static let subtasksDone = 1
    static let subtasks = 2
}
