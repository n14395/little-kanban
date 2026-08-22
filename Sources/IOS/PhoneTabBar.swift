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

    private var tabPill: some View {
        HStack(spacing: 4) {
            ForEach(PhoneTab.allCases) { tab in
                // A saved view has replaced the list, so none of the three
                // places the tabs name is what is on screen; highlighting one
                // of them anyway would be the drawer's inert rows over again.
                let isCurrent = store.activeView == nil && store.tab == tab
                Button { store.selectTab(tab) } label: {
                    Text(tab.label)
                        .font(SimpleKanbanFont.ui(12, isCurrent ? .extraBold : .bold, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? palette.accent : palette.inkText(0.45))
                        // Three single words in three equal thirds of a phone.
                        // At an accessibility size they do not fit, and a word
                        // has nowhere to break: the pill read "Boar / d",
                        // "Inbo / x", "Sear / ch". Held to one line and allowed
                        // to shrink, they still grow with the reader's text —
                        // just not past the slot they have to sit in.
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isCurrent ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
                        // The selected chip is drawn at the design's height;
                        // the tab claims the 44pt minimum around it.
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bare)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
