import AudioToolbox
import Foundation
#if os(macOS)
import AppKit
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
/// **Haptics are split by platform on purpose.** The phone's card performs the
/// `.success` tap itself (`PhoneTaskCard`, item 5.8) — `sensoryFeedback` is
/// the right instrument there, and a second tap from here would knock twice.
/// The desk has no such view, so the trackpad's knock is performed here; on a
/// Mac without a haptic trackpad it is a no-op, which is what "devices that
/// support it" comes to.
@MainActor
final class CompletionFeedback {
    static let shared = CompletionFeedback()

    private var gate = ChimeGate()

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
        #endif
    }
}
