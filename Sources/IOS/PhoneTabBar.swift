#if os(iOS)

import SwiftUI

/// The floating tab pill and quick-capture button.
///
/// The design asks for a blurred, tinted bar here (`--glass` + `backdrop-filter`),
/// which is exactly what Liquid Glass provides natively. Both controls live in a
/// single `GlassEffectContainer` so their materials blend the way two adjacent
/// floating elements should.
struct PhoneTabBar: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                tabPill
                quickCaptureButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: palette.appBackground.opacity(0), location: 0),
                    .init(color: palette.appBackground.opacity(0.96), location: 0.6),
                    .init(color: palette.appBackground.opacity(0.96), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Two destinations and a toggle, drawn as three equal slots.
    ///
    /// **The Inbox is the toggle**, and it sits between them rather than at
    /// either end because that is where it was when it was a tab and because it
    /// is the one thing on this bar you reach for *while* on a board. It raises
    /// ``PhoneInboxSheet`` over whatever is on screen instead of replacing it —
    /// so unlike the other two it does not answer "where am I", and it reads as
    /// current whenever the panel is up, over a saved view included.
    private var tabPill: some View {
        HStack(spacing: 4) {
            slot(PhoneTab.board.label, isCurrent: isCurrent(.board)) { store.selectTab(.board) }
            slot(Board.inboxName, isCurrent: store.isInboxOpen) { store.toggleInbox() }
            slot(PhoneTab.search.label, isCurrent: isCurrent(.search)) { store.selectTab(.search) }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// A saved view has replaced the list, so neither place the tabs name is
    /// what is on screen; highlighting one anyway would be the drawer's inert
    /// rows over again. The Inbox does not go through this — a panel over the
    /// top is showing whether or not a view is under it.
    private func isCurrent(_ tab: PhoneTab) -> Bool {
        store.activeView == nil && store.tab == tab
    }

    private func slot(_ title: String, isCurrent: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(SimpleKanbanFont.ui(12, isCurrent ? .extraBold : .bold, relativeTo: .caption))
                .foregroundStyle(isCurrent ? palette.accent : palette.inkText(0.45))
                // Three single words in three equal thirds of a phone. At an
                // accessibility size they do not fit, and a word has nowhere to
                // break: the pill read "Boar / d", "Inbo / x", "Sear / ch".
                // Held to one line and allowed to shrink, they still grow with
                // the reader's text — just not past the slot they sit in.
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isCurrent ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
                // The selected chip is drawn at the design's height; the slot
                // claims the 44pt minimum around it.
                .frame(minHeight: 44)
        }
        .buttonStyle(.bare)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private var quickCaptureButton: some View {
        Button {
            store.quickCapture()
        } label: {
            Image(systemName: "plus")
                .symbolSize(24, weight: .regular, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                .frame(minWidth: 52, minHeight: 52)
        }
        .buttonStyle(.bare)
        .glassEffect(.regular.tint(palette.accent).interactive(), in: .circle)
        .accessibilityLabel("New task")
    }
}

#endif
