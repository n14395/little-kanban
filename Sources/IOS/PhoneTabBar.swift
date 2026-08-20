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
                let isCurrent = store.tab == tab
                Button { store.tab = tab } label: {
                    Text(tab.label)
                        .font(SimpleKanbanFont.ui(12, isCurrent ? .extraBold : .bold, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? palette.accent : palette.ink(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isCurrent ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.bare)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var quickCaptureButton: some View {
        Button { store.quickCapture() } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.bare)
        .glassEffect(.regular.tint(palette.accent).interactive(), in: .circle)
        .accessibilityLabel("New task")
    }
}

#endif
