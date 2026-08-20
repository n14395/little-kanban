#if os(iOS)

import SwiftUI

/// The iPhone screen: header, optional pager, task list, floating tab bar,
/// plus the drawer and detail sheet overlays.
struct PhoneRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PhoneHeader()
                    .padding(.top, 4)

                if store.tab == .board {
                    PhoneColumnPager()
                }

                taskList
            }

            PhoneTabBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.appBackground.ignoresSafeArea())
        .overlay {
            if store.isNavDrawerOpen {
                PhoneNavDrawer()
            }
        }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28), value: store.isNavDrawerOpen)
        .sheet(isPresented: sheetBinding) {
            if let task = store.sheetTask {
                PhoneDetailSheet(task: task)
                    .environment(store)
                    .environment(\.palette, palette)
                    .environment(\.dayClock, dayClock)
            }
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.mobileTasks) { task in
                    PhoneTaskCard(task: task)
                }

                if store.showsMobileAddRow {
                    Button { store.addTaskToCurrentMobileColumn() } label: {
                        Text("+ Add task to \(store.mobileColumnName)")
                            .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
                            .foregroundStyle(palette.ink(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(
                                        palette.ink(0.18),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                                    )
                            }
                    }
                    .buttonStyle(.bare)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 130)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { store.sheetID != nil },
            set: { if !$0 { store.sheetID = nil } }
        )
    }
}

#endif
