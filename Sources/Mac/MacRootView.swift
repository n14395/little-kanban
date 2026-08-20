#if os(macOS)

import SwiftUI

/// The macOS window body: sidebar, board, optional inspector, status strip.
struct MacRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            MacSidebar()

            VStack(spacing: 0) {
                MacToolbar()

                HStack(spacing: 0) {
                    MacBoardView()
                    if store.isInspectorOpen, let task = store.selectedTask {
                        MacInspector(task: task)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                MacStatusBar()
            }
        }
        .background(palette.window)
        .frame(minWidth: 940, minHeight: 620)
        .animation(.easeOut(duration: 0.16), value: store.isInspectorOpen)
        .animation(.easeOut(duration: 0.16), value: store.selectedID)
    }
}

#endif
