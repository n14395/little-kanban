import SwiftUI

/// Whether this launch is somebody's first.
///
/// Two facts rather than one, because either on its own is wrong. The
/// preference alone would put the picker in front of everybody upgrading from a
/// build that predates it, and they have a board already. The file alone would
/// put it back in front of anybody who chose the empty board and quit before
/// typing anything, because nothing was ever written.
///
/// Answered **once**, and before ``BoardStore`` is built: building it is what
/// creates the file this asks about.
enum FirstRun {
    static let storageKey = "SimpleKanbanChoseStarter"

    /// The picker stands between a launch argument and the board it means to
    /// drive, so a harness needs to be able to say which it wants:
    ///
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanFirstRun YES
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanSkipFirstRun YES
    ///
    /// A *forced* first run is not one: there is a board on this machine, and
    /// `emptyStore` hands the session a throwaway file rather than the real one
    /// — an empty store pointed at somebody's board would write over it the
    /// moment the app was quit.
    #if DEBUG
    static let isForced = UserDefaults.standard.bool(forKey: "SimpleKanbanFirstRun")
    #endif

    static let isPending: Bool = {
        #if DEBUG
        if isForced { return true }
        if UserDefaults.standard.bool(forKey: "SimpleKanbanSkipFirstRun") { return false }
        #endif
        // The suite launches this app as its test host, and a test host that
        // stops at a modal picker is a test host with no board on it.
        guard !BoardFile.isRunningTests else { return false }
        guard !UserDefaults.standard.bool(forKey: storageKey) else { return false }
        return !FileManager.default.fileExists(
            atPath: BoardFile.default.url.path(percentEncoded: false)
        )
    }()

    /// The board a first launch starts on: nothing at all, which is what the
    /// picker then folds a template into. Deliberately not the seed — the whole
    /// point of the picker is that nobody is handed the sample without asking
    /// for it — and deliberately not `restored()`, which would seed.
    @MainActor
    static func emptyStore(file: BoardFile = .default) -> BoardStore {
        var file = file
        #if DEBUG
        if isForced {
            file = BoardFile(url: URL.temporaryDirectory
                .appending(path: "SimpleKanbanFirstRun-\(UUID().uuidString)/board.json"))
        }
        #endif
        return BoardStore(tasks: [], boards: [], labels: [], file: file)
    }
}

/// The picker: five boards to start from, one of which is empty.
///
/// A first launch opens on it, and **Settings ▸ Delete everything** opens it
/// again — the same five rows, because "what should be on this board" has one
/// answer whether it is being asked for the first time or the second.
///
/// A modal with no way past it that is not a choice. There is no Skip, because
/// the empty board *is* the skip and saying so is more honest than a link in
/// the corner that quietly picks for you.
struct FirstRunView: View {
    /// Why the picker is up. The rows are identical either way; the words
    /// around them are not, and only one of the two can be called off.
    ///
    /// A first launch has nothing to lose, so it has no way out but a choice.
    /// Starting over has a whole board to lose, so it has a Cancel — and
    /// nothing is thrown away until a row is picked, which is what makes the
    /// Cancel mean anything.
    enum Occasion: CaseIterable {
        case firstLaunch
        case startingOver
    }

    struct Metrics {
        /// A fixed sheet on the desk; the whole screen on a phone.
        var width: CGFloat?
        /// What the desk's sheet opens at. A sheet wrapped round a scroll view
        /// has no height of its own to be sized to.
        var minHeight: CGFloat?
        var padding: CGFloat
        var headerSpacing: CGFloat
        var rowSpacing: CGFloat
        var title: CGFloat
        var subtitle: CGFloat
        var rowTitle: CGFloat
        var rowNote: CGFloat
        var columnLabel: CGFloat
        /// The row's floor. A finger needs 44; a pointer claims nothing.
        var rowHit: CGFloat
        var panelRadius: CGFloat
        var dot: CGFloat
        var footnote: CGFloat

        static let desk = Metrics(
            width: 480, minHeight: 560, padding: 22, headerSpacing: 8, rowSpacing: 0,
            title: 26, subtitle: 12.5, rowTitle: 14, rowNote: 11.5, columnLabel: 10.5,
            rowHit: 0, panelRadius: 12, dot: 7, footnote: 11
        )
        static let sheet = Metrics(
            width: nil, minHeight: nil, padding: 20, headerSpacing: 10, rowSpacing: 0,
            title: 32, subtitle: 15, rowTitle: 17, rowNote: 13.5, columnLabel: 12,
            rowHit: 44, panelRadius: 14, dot: 8, footnote: 12.5
        )
    }

    @Environment(\.palette) private var palette

    var metrics: Metrics = .desk
    var occasion: Occasion = .firstLaunch
    let templates: [BoardTemplate]
    let choose: (BoardTemplate) -> Void
    /// Present only when there is something to keep. Its absence is what makes
    /// a first launch inescapable, so it doubles as the flag for that.
    var cancel: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.padding) {
                header
                VStack(spacing: metrics.rowSpacing) {
                    ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                        if index > 0 { rule }
                        row(template)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: metrics.panelRadius)
                        .fill(palette.card)
                        .shadow(color: palette.shadow(0.06), radius: 8, y: 2)
                }
                footer
            }
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: metrics.width)
        .frame(minHeight: metrics.minHeight)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
        // Every way out of a first launch is a choice, so there is no way out
        // that is not. Starting over can be called off, and a swipe down is
        // what somebody reaches for to do it.
        .interactiveDismissDisabled(cancel == nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(palette.display(metrics.title))
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let cancel { cancelButton(cancel) }
            }
            Text(subtitle)
                .font(palette.ui(metrics.subtitle, .medium, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cancelButton(_ cancel: @escaping () -> Void) -> some View {
        Button(role: .cancel, action: cancel) {
            Text("Cancel", comment: "Button that closes the starter picker leaving the board alone")
                .font(palette.ui(metrics.rowTitle, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.accent)
                // A finger needs 44 and a pointer claims nothing, the same rule
                // the rows follow. `.contentShape` because a `.bare` button
                // hit-tests the glyphs it draws and nothing else.
                .frame(minHeight: metrics.rowHit)
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .keyboardShortcut(.cancelAction)
    }

    private var title: String { occasion.title }
    private var subtitle: String { occasion.subtitle }

    private var rule: some View {
        Rectangle().fill(palette.ink(0.06)).frame(height: 1)
    }

    private func row(_ template: BoardTemplate) -> some View {
        Button { choose(template) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.symbol)
                    .imageScale(.medium)
                    .foregroundStyle(palette.accent)
                    .frame(width: metrics.rowTitle + 8)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(palette.ui(metrics.rowTitle, .bold, relativeTo: .headline))
                        .foregroundStyle(palette.ink)
                    Text(template.blurb)
                        .font(palette.ui(metrics.rowNote, .medium, relativeTo: .footnote))
                        .foregroundStyle(palette.ink(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    columnPreview(template)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(palette.ink(0.3))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: metrics.rowHit)
            .hoverBackground(palette.ink(0.05), radius: metrics.panelRadius)
        }
        .buttonStyle(.bare)
        // The columns and the count are the preview; to VoiceOver they are a
        // sentence, because a row of five unlabelled dots is not one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(template.name)
        .accessibilityValue(Self.summary(template))
        .accessibilityHint(Text("Starts a board from this template",
                                comment: "First-run picker row hint"))
    }

    /// The board's own column dots, in board order, with the card count after
    /// them — the smallest honest preview of what choosing this does.
    private func columnPreview(_ template: BoardTemplate) -> some View {
        HStack(spacing: 6) {
            ForEach(template.columns) { column in
                Circle()
                    .fill(palette.resolve(column.dot))
                    .frame(width: metrics.dot, height: metrics.dot)
            }
            Text(Self.summary(template))
                .font(palette.ui(metrics.columnLabel, .semibold, relativeTo: .caption2))
                .foregroundStyle(palette.ink(0.38))
                .padding(.leading, 2)
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        Text(footnote)
            .font(palette.ui(metrics.footnote, .medium, relativeTo: .caption))
            .foregroundStyle(palette.ink(0.38))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footnote: String { occasion.footnote }

    /// "5 columns · 8 cards", and the empty board says so in words rather than
    /// claiming nought of something.
    ///
    /// The card count is what the *columns* hold. A template may also carry
    /// unfiled cards — the sample board's three are the design's Inbox — and
    /// counting those beside the columns promises cards the board does not
    /// show, so they get their own clause.
    static func summary(_ template: BoardTemplate) -> String {
        let columns = String(
            localized: "\(template.columns.count) columns",
            comment: "First-run picker: how many columns a template has"
        )
        let filed = template.tasks.count { !$0.isUnfiled }
        let unfiled = template.tasks.count - filed

        var clauses = [columns]
        if filed > 0 {
            clauses.append(String(
                localized: "\(filed) cards",
                comment: "First-run picker: how many cards a template puts on the board"
            ))
        }
        if unfiled > 0 {
            clauses.append(String(
                localized: "\(unfiled) in the Inbox",
                comment: "First-run picker: how many of a template's cards start unfiled"
            ))
        }
        guard clauses.count > 1 else {
            return String(localized: "\(columns) · empty",
                          comment: "First-run picker: a template with no cards on it")
        }
        return clauses.joined(separator: " · ")
    }
}

/// What the picker says around the rows.
///
/// On the occasion rather than in the view because the difference between the
/// two is entirely in these three strings — and because a picker that still
/// says *Welcome to Simple Kanban* while it is about to replace somebody's
/// board is the failure this whole arrangement exists to avoid, which
/// `StartingOverTests` can only check if it can read them.
extension FirstRunView.Occasion {
    var title: String {
        switch self {
        case .firstLaunch:
            String(localized: "Welcome to Simple Kanban", comment: "First-run picker title")
        case .startingOver:
            String(localized: "Start over", comment: "Starter picker title when a board is being replaced")
        }
    }

    var subtitle: String {
        switch self {
        case .firstLaunch:
            String(localized: "Pick a board to start from. Everything on it is yours to rename, move or throw away, and you can add boards of your own whenever you like.",
                   comment: "First-run picker subtitle")
        case .startingOver:
            String(localized: "Pick what to start from. Every board, card and label you have now is replaced by what you choose here.",
                   comment: "Starter picker subtitle when a board is being replaced")
        }
    }

    var footnote: String {
        switch self {
        case .firstLaunch:
            String(localized: "Nothing here is sent anywhere. The board is a file on this device, and Settings can replace it at any time.",
                   comment: "First-run picker footnote")
        case .startingOver:
            String(localized: "Nothing is thrown away until you pick one. A copy of the board as it stands is kept in the backups folder first, and the change can be undone.",
                   comment: "Starter picker footnote when a board is being replaced")
        }
    }
}

extension View {
    /// Puts the starter picker on screen the way the platform wants it: a cover
    /// on the phone, where there is nothing behind it worth looking at, and a
    /// sheet on the desk.
    ///
    /// Shared by the two places that raise it — the launch with no board yet,
    /// and the Settings row that throws one away — so the platform choice and
    /// the metrics that go with it cannot drift between them.
    ///
    /// `palette` is passed rather than read, because a modifier sits *above*
    /// the `.environment(\.palette,)` the root applies below it: what it would
    /// read is the default light palette, which is how a picker comes to open
    /// cream-coloured over a dark board.
    func starterPicker(
        isPresented: Binding<Bool>,
        occasion: FirstRunView.Occasion,
        palette: Palette,
        choose: @escaping (BoardTemplate) -> Void,
        cancel: (() -> Void)? = nil
    ) -> some View {
        modifier(StarterPicker(isPresented: isPresented, occasion: occasion,
                               palette: palette, choose: choose, cancel: cancel))
    }
}

private struct StarterPicker: ViewModifier {
    @Binding var isPresented: Bool
    let occasion: FirstRunView.Occasion
    let palette: Palette
    let choose: (BoardTemplate) -> Void
    let cancel: (() -> Void)?

    private static var metrics: FirstRunView.Metrics {
        #if os(macOS)
        .desk
        #else
        .sheet
        #endif
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) { picker }
        #else
        content.sheet(isPresented: $isPresented) { picker }
        #endif
    }

    private var picker: some View {
        FirstRunView(
            metrics: Self.metrics, occasion: occasion, templates: SeedData.starters,
            choose: choose, cancel: cancel
        )
        .environment(\.palette, palette)
        .tint(palette.accent)
        .foregroundStyle(palette.ink)
    }
}

#Preview("First run") {
    FirstRunView(metrics: .desk, templates: SeedData.starters) { _ in }
        .environment(\.palette, Palette(theme: ThemePresets.fallback(for: .light)))
        .frame(height: 720)
}

#Preview("Starting over") {
    FirstRunView(metrics: .desk, occasion: .startingOver, templates: SeedData.starters,
                 choose: { _ in }, cancel: {})
        .environment(\.palette, Palette(theme: ThemePresets.fallback(for: .light)))
        .frame(height: 720)
}
