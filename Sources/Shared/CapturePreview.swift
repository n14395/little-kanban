import SwiftUI

/// What the composer is about to take out of the line, and the way to stop it.
///
/// **Nothing is consumed silently.** `CaptureParse` reads a typed title for
/// `#bug`, `!high` and a trailing date, and a grammar that quietly rewrites what
/// somebody typed is one they cannot argue with — the only recourse would be to
/// commit the card and then repair it. So the reading is shown before it
/// happens, one chip per token, and every chip is a button that hands that token
/// back: the words stay in the title and nothing is set.
///
/// **It is absent until it has something to say.** A person who never types a
/// token never sees this, and the composer is exactly the height it always was.
/// That is what makes the feature safe to leave switched on by default — it
/// costs nothing until it fires, and when it fires it says so.
///
/// The chips are one uniform shape rather than the real `LabelChip` and
/// `DueChip`. Those draw the card as it *will look*, and this row is answering a
/// different question — "what am I about to take from you, and do you want it
/// back" — so the tokens read as one list of claims with one way to refuse them,
/// instead of a scattering of controls that each behave differently.
struct CapturePreview: View {
    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    private var chrome = ChromeScale()

    let parse: CaptureParse
    /// Touch surfaces run the row larger, the same split every other chip makes.
    var isCompact = true
    /// What to do with a token the user hands back. A closure rather than a
    /// reach into the store, because the two fields that draw this keep their
    /// drafts in different places: the composer's is the store's, and the menu
    /// bar extra's is its own `@State` — it outlives whichever board window is
    /// open and has no business writing session state onto the board.
    let reject: (CaptureParse.Token) -> Void

    init(parse: CaptureParse, isCompact: Bool = true, reject: @escaping (CaptureParse.Token) -> Void) {
        self.parse = parse
        self.isCompact = isCompact
        self.reject = reject
    }

    var body: some View {
        FlowLayout(spacing: chrome(isCompact ? 5 : 6)) {
            ForEach(parse.taken) { token in
                chip(for: token)
            }
        }
    }

    private func chip(for token: CaptureParse.Token) -> some View {
        Button {
            reject(token)
        } label: {
            HStack(spacing: chrome(isCompact ? 4 : 5)) {
                Image(systemName: symbol(for: token.meaning))
                    .symbolSize(font - 1.5, weight: .semibold, relativeTo: .caption)
                Text(text(for: token.meaning))
                    .font(palette.ui(font, .semibold, relativeTo: .caption))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .symbolSize(font - 3, weight: .bold, relativeTo: .caption2)
                    .opacity(0.55)
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, chrome(isCompact ? 7 : 9))
            .padding(.vertical, chrome(isCompact ? 3 : 5))
            .background(palette.accentSoft, in: .rect(cornerRadius: chrome(isCompact ? 6 : 8)))
        }
        .buttonStyle(.bare)
        // The chip is a claim being made and a way to refuse it, and the glyph
        // says neither out loud. Both halves are spoken, because a row of chips
        // called "Bug" and "Friday" with no verb is a row VoiceOver reads as
        // decoration — and this is the only place the grammar can be argued
        // with.
        .accessibilityLabel(spokenLabel(for: token.meaning))
        .accessibilityHint(Text("Keeps the words in the title instead",
                                comment: "VoiceOver hint on a quick-capture preview chip"))
        .help(Text("Keep “\(token.text)” in the title",
                   comment: "Tooltip on a quick-capture preview chip: the token as it was typed"))
    }

    private var font: CGFloat { isCompact ? 10.5 : 12 }

    private func symbol(for meaning: CaptureParse.Token.Meaning) -> String {
        switch meaning {
        case .due: "calendar"
        case .priority: "flag.fill"
        case .label: "tag.fill"
        }
    }

    /// What the chip says. The due chip names the **resolved** day rather than
    /// echoing "next friday" back: the whole ambiguity in "next" is which Friday
    /// it landed on, and repeating the words the user typed answers nothing.
    private func text(for meaning: CaptureParse.Token.Meaning) -> String {
        switch meaning {
        case .due(let day): Self.spellOut(day, from: dayClock.today)
        case .priority(let priority): priority.displayName
        case .label(_, let name): name
        }
    }

    /// **Not `DueDate.label`**, which is the chip a *card* wears. That one is
    /// tuned for reading a column at a glance and goes vague on purpose beyond
    /// the coming week — a date eleven days out reads "Next week", and a
    /// confirmation that says "next week" to somebody who just typed "next
    /// friday" has confirmed nothing. This is the one place the exact day is the
    /// whole point, so past tomorrow it is spelled: "Fri 18 Sep".
    ///
    /// Today and tomorrow keep the words, because those are the two days a date
    /// is not what anybody is checking.
    static func spellOut(_ day: CalendarDay, from today: CalendarDay) -> String {
        switch DueDate.daysAway(day, from: today) {
        case 0, 1: DueDate.label(day, from: today)
        default: day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    private func spokenLabel(for meaning: CaptureParse.Token.Meaning) -> Text {
        switch meaning {
        case .due(let day):
            Text("Remove due date \(DueDate.accessibilityLabel(day, from: dayClock.today))",
                 comment: "VoiceOver label for a quick-capture preview chip carrying a due date")
        case .priority(let priority):
            Text("Remove priority \(priority.displayName)",
                 comment: "VoiceOver label for a quick-capture preview chip carrying a priority")
        case .label(_, let name):
            Text("Remove label \(name)",
                 comment: "VoiceOver label for a quick-capture preview chip carrying a task label")
        }
    }
}
