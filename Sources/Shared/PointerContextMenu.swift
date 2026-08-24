import SwiftUI
#if os(iOS)
import Observation
import UIKit
#endif

extension View {
    /// A context menu for a pointer, and only a pointer: right-click raises it,
    /// a finger's long press does not.
    ///
    /// On the desk this is `.contextMenu` unchanged — AppKit only ever raised
    /// that on a right-click. The modifier exists for the other platform, where
    /// one modifier answers two inputs: UIKit hangs the same menu off a
    /// pointer's secondary click *and* a touch long-press, and offers no switch
    /// to keep the first while declining the second. On a card that is also
    /// draggable the long-press menu is worse than a duplicate — holding a card
    /// is how a finger *picks it up*, and a menu on the same hold means every
    /// lift starts with a popup to escape from.
    ///
    /// So on iOS the menu stays attached — which is what keeps right-click
    /// working, on the view the drag also sits on, see ``ReorderableCard`` for
    /// why that placement matters — and its *items* are gated on the input that
    /// is raising it: ``PointerOnlyContextMenu`` has the mechanism. A menu whose
    /// builder yields nothing is a menu SwiftUI does not raise, so the long
    /// press falls through to the drag underneath it, with no lift preview and
    /// no cancelled-menu flash.
    ///
    /// **What a gated menu owes VoiceOver.** UIKit surfaces context-menu items
    /// as custom actions, and a reader drives by touch — to them the gate is
    /// always closed. Every surface that trades its menu for this must carry
    /// the same verbs as explicit accessibility actions; both cards do.
    @ViewBuilder
    func pointerContextMenu<Items: View>(@ViewBuilder items: @escaping () -> Items) -> some View {
        #if os(macOS)
        contextMenu(menuItems: items)
        #else
        modifier(PointerOnlyContextMenu(items: items))
        #endif
    }
}

#if os(iOS)

/// The gate and its two informants.
///
/// The question is "what input is raising this menu right now", and nothing on
/// the SwiftUI side can answer it — `contextMenu` does not say, and by the time
/// an item's action runs the answer no longer matters. What can answer it is
/// UIKit's own delivery order: every event is *hit-tested* down the view tree
/// before anything recognises it, so a transparent view laid over the card sees
/// the touch that will become the menu — finger or pointer, read off the
/// event's `buttonMask` — before the menu machinery does, and can set the gate
/// the items builder then reads.
///
/// The timing holds from either end. SwiftUI evaluates a context menu's items
/// when the menu is about to present — it is why these menus show fresh state —
/// so the builder's read of `isOpen` lands *after* the sensor's write from the
/// very event being decided. And should some build evaluate eagerly instead,
/// the gate is `@Observable`, so a flipped gate re-renders the items long
/// before a long press's half-second fuse burns down; only the first
/// right-click after a touch could land stale, and `onHover` — a pointer's
/// arrival, always well ahead of its click — reopens the gate for exactly that
/// case. A hover is also the one pointer signal a finger can never fake, which
/// is why it only ever opens.
struct PointerOnlyContextMenu<Items: View>: ViewModifier {
    @State private var gate = PointerGate()

    /// A closure rather than a built value: taking `Items` meant every card
    /// paid to construct its whole menu on every render whether or not a
    /// pointer was anywhere near it. Behind the gate, a finger-driven render
    /// builds nothing.
    let items: () -> Items

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if gate.isOpen { items() }
            }
            .overlay { PointerSensor(gate: gate) }
            .onHover { entered in
                if entered { gate.open() }
            }
    }
}

/// Whether the last input aimed at the card was a pointer's. A class rather
/// than view state because the menu's items builder reads it at presentation
/// time, from outside any render pass; observable so a build that reads it
/// *during* one is told when it changes.
@Observable @MainActor
private final class PointerGate {
    private(set) var isOpen = false

    func open() { if !isOpen { isOpen = true } }
    func close() { if isOpen { isOpen = false } }
}

private struct PointerSensor: UIViewRepresentable {
    let gate: PointerGate

    func makeUIView(context: Context) -> PointerSensorView {
        PointerSensorView(gate: gate)
    }

    func updateUIView(_ view: PointerSensorView, context: Context) {
        view.gate = gate
    }
}

/// The observer: frontmost over the card, asked first, and never the answer.
///
/// `hitTest` returning nil is what makes this safe to lay over a card that is
/// a button, a drag source and a drop target at once — the recursion carries on
/// past it to whatever was there before, and the view consumes nothing. All it
/// does on the way through is read the event: a pointer's click arrives with a
/// button in its mask, a finger's (or a pencil's) with none, and either way the
/// event seen *is* the one about to be recognised, so the gate cannot say
/// yesterday's answer. Non-touch traffic — hover reads, scrolls — is let past
/// without a verdict; hover has its own line into the gate above.
private final class PointerSensorView: UIView {
    var gate: PointerGate

    init(gate: PointerGate) {
        self.gate = gate
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let event, event.type == .touches {
            if event.buttonMask.isEmpty { gate.close() } else { gate.open() }
        }
        return nil
    }
}

#endif
