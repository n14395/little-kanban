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

/// The picker a first launch opens with: five boards to start from, one of
/// which is empty.
///
/// A modal with no way past it that is not a choice. There is no Skip, because
/// the empty board *is* the skip and saying so is more honest than a link in
/// the corner that quietly picks for you.
struct FirstRunView: View {
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
    let templates: [BoardTemplate]
    let choose: (BoardTemplate) -> Void

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
        .background(palette.appBackground)
        .presentationBackground(palette.appBackground)
        // Every way out of this is a choice, so there is no way out that is not.
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            Text("Welcome to Simple Kanban", comment: "First-run picker title")
                .font(SimpleKanbanFont.serif(metrics.title))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Pick a board to start from. Everything on it is yours to rename, move or throw away, and you can add boards of your own whenever you like.",
                 comment: "First-run picker subtitle")
                .font(SimpleKanbanFont.ui(metrics.subtitle, .medium, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

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
                        .font(SimpleKanbanFont.ui(metrics.rowTitle, .bold, relativeTo: .headline))
                        .foregroundStyle(palette.ink)
                    Text(template.blurb)
                        .font(SimpleKanbanFont.ui(metrics.rowNote, .medium, relativeTo: .footnote))
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
                .font(SimpleKanbanFont.ui(metrics.columnLabel, .semibold, relativeTo: .caption2))
                .foregroundStyle(palette.ink(0.38))
                .padding(.leading, 2)
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        Text("Nothing here is sent anywhere. The board is a file on this device, and Settings can replace it with the sample at any time.",
             comment: "First-run picker footnote")
            .font(SimpleKanbanFont.ui(metrics.footnote, .medium, relativeTo: .caption))
            .foregroundStyle(palette.ink(0.38))
            .fixedSize(horizontal: false, vertical: true)
    }

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

#Preview("First run") {
    FirstRunView(metrics: .desk, templates: SeedData.starters) { _ in }
        .environment(\.palette, Palette(colorScheme: .light))
        .frame(height: 720)
}
