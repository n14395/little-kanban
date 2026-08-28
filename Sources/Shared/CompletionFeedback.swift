import AudioToolbox
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// One chime per act, however many cards the act finished.
///
/// A bulk complete runs one `performMove` per card inside a single turn, and a
/// ding per card is a slot machine. The gate passes the first announcement of
/// a burst and swallows the rest; wide enough to cover a loop that finishes
/// two hundred cards, narrow enough that two ticks made a second apart both
/// sound.
struct ChimeGate {
    var interval: TimeInterval = 0.3
    private var last = Date.distantPast

    mutating func admits(_ now: Date = .now) -> Bool {
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}

/// The sound and the tap a card makes on its way into Done.
///
/// The store announces — `performMove`, on the one transition that means a
/// card was finished — and this object decides, so every route in is covered:
/// the tick, the context menu, the keyboard, a drag onto the Done column, a
/// bulk complete. Undo, redo and a sync merge restore state without passing
/// through `performMove`, which is the point: they put a board back, and a
/// board being put back is not something being finished.
///
/// **The tap is performed here on every platform**, and it used to be split:
/// the phone's card carried its own `.success` through `sensoryFeedback`, on
/// the argument that SwiftUI's instrument is the right one where there is a
/// view to hang it on. There is a view, and it was the wrong view.
/// `sensoryFeedback` fires when the value it watches changes on a view that is
/// *still in the tree*, and finishing a card on a board takes it out of the
/// tree: the card moves to Done and the column page it was on stops drawing it,
/// so the modifier went away with the row that owned it. The tap therefore
/// arrived in the Inbox — where a completed capture stays put and merely goes
/// grey — and nowhere else on the phone, which is not a platform split anybody
/// designed. This announcement is the one thing that knows a card was finished
/// whether or not something is still drawing it, and it is already here for the
/// chime. On hardware with nothing to knock — a Mac without a haptic trackpad,
/// any iPad — it is a no-op.
@MainActor
final class CompletionFeedback {
    static let shared = CompletionFeedback()

    private var gate = ChimeGate()

    #if os(iOS)
    /// Kept rather than made per tap: the generator is the thing the system
    /// warms, and one built at the moment it is asked to fire has nothing
    /// warmed. `.success` is the same tap the card used to perform — SwiftUI's
    /// `.success` is this generator underneath.
    private let taps = UINotificationFeedbackGenerator()
    #endif

    /// Loaded chimes, one system sound per preset, created on first play and
    /// kept — `AudioServicesCreateSystemSoundID` reads the file each time.
    private var loaded: [CompletionSound: SystemSoundID] = [:]

    /// `false` under tests: the suite completes cards by the hundred, and each
    /// one would ding the developer's speakers and knock their trackpad —
    /// `scheduleSave` makes the same bargain for reminders and Spotlight.
    private let reachesTheMachine: Bool

    init(reachesTheMachine: Bool = !BoardFile.isRunningTests) {
        self.reachesTheMachine = reachesTheMachine
    }

    /// The store's announcement: a card has just reached Done by someone's
    /// hand. The haptic is not behind the sound switch — the switch is about
    /// the noise, and a silent tap is exactly what someone who turned the
    /// noise off still gets.
    func taskCompleted(now: Date = .now) {
        guard gate.admits(now), reachesTheMachine else { return }
        haptic()
        guard Preferences.playsCompletionSound else { return }
        play(Preferences.completionSound)
    }

    /// The settings picker's audition. It plays whatever the toggle says,
    /// because choosing a sound while the switch is off is still a question
    /// about the sound.
    func preview(_ sound: CompletionSound) {
        guard reachesTheMachine else { return }
        play(sound)
    }

    /// `AudioServices` rather than an `AVAudioPlayer`: a UI sound should ride
    /// the system's short-sound path — nothing to configure, no session to
    /// hold, and the phone's silent switch is respected rather than argued
    /// with.
    private func play(_ sound: CompletionSound) {
        guard let id = soundID(for: sound) else { return }
        AudioServicesPlaySystemSound(id)
    }

    private func soundID(for sound: CompletionSound) -> SystemSoundID? {
        if let id = loaded[sound] { return id }
        guard let url = Bundle.main.url(
            forResource: sound.resourceName, withExtension: "caf", subdirectory: "Sounds"
        ) else { return nil }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return nil }
        loaded[sound] = id
        return id
    }

    private func haptic() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #elseif os(iOS)
        taps.notificationOccurred(.success)
        #endif
    }
}
