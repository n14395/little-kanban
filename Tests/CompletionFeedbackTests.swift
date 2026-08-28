import Foundation
import Testing
@testable import Simple_Kanban

/// The chime's plumbing: the preference vocabulary, the gate that keeps a bulk
/// complete to one sound, and the promise that every preset names a file the
/// bundle actually carries. The sound itself is not driven from here —
/// `CompletionFeedback` is built deaf under tests, the way the scheduler is
/// built without a notification centre — so what is tested is everything that
/// decides whether and what it would play.
@Suite struct CompletionFeedbackTests {
    // MARK: The preferences

    @MainActor
    @Test func theSoundIsOnByDefaultAndTheChimeIsTheFallback() throws {
        let suite = try #require(UserDefaults(suiteName: "SimpleKanbanTests-\(UUID().uuidString)"))
        Preferences.reading(suite) {
            #expect(Preferences.playsCompletionSound, "a fresh install should ding")
            #expect(Preferences.completionSound == .chime)
        }
    }

    @MainActor
    @Test func theStoredChoiceComesBackAndAStrangerFallsBack() throws {
        let suite = try #require(UserDefaults(suiteName: "SimpleKanbanTests-\(UUID().uuidString)"))
        suite.set(false, forKey: Preferences.completionSoundKey)
        suite.set(CompletionSound.glass.rawValue, forKey: CompletionSound.storageKey)
        Preferences.reading(suite) {
            #expect(!Preferences.playsCompletionSound)
            #expect(Preferences.completionSound == .glass)
        }
        // A downgrade leaves a raw value this build has no case for. The
        // fallback answers — the same reading every `Preferences.choice` gives
        // a stranger.
        suite.set("kazoo", forKey: CompletionSound.storageKey)
        Preferences.reading(suite) {
            #expect(Preferences.completionSound == .chime)
        }
    }

    // MARK: The gate

    /// A bulk complete runs one announcement per card inside a single turn,
    /// and one act is one chime — while two ticks made a beat apart are two
    /// acts and get two.
    @Test func aBurstOfCompletionsIsOneChime() {
        var gate = ChimeGate()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let first = gate.admits(start)
        let sameInstant = gate.admits(start)
        let sameBurst = gate.admits(start.addingTimeInterval(0.1))
        let aBeatLater = gate.admits(start.addingTimeInterval(0.35))
        let onItsHeels = gate.admits(start.addingTimeInterval(0.4))
        #expect(first, "the first of a burst plays")
        #expect(!sameInstant, "the rest of the same turn is the same act")
        #expect(!sameBurst)
        #expect(aBeatLater, "a tick a beat later is its own act")
        #expect(!onItsHeels, "and re-arms the gate behind it")
    }

    // MARK: Where the tap is performed

    /// **The tap belongs to the announcement, not to the card.**
    ///
    /// `PhoneTaskCard` used to carry its own `.success` `sensoryFeedback` keyed
    /// on `isDone`. That modifier fires when the value changes on a view still
    /// in the tree, and finishing a card on a board takes it out of the tree —
    /// the card moves to Done and the column page stops drawing it — so the tap
    /// went away with the row that owned it. It arrived in the Inbox, where a
    /// completed capture stays put and merely goes grey, and nowhere else on the
    /// phone: a platform split nobody designed, reported as "done gives haptic
    /// feedback in the Inbox and not on the board".
    ///
    /// Read out of the source, because whether a modifier *fires* is not
    /// something a unit test can observe — and the bug was the modifier being
    /// there at all. `CompletionFeedback.taskCompleted()` is announced by
    /// `BoardStore` on both completion paths, so it knows a card was finished
    /// whether or not anything is still drawing it.
    @Test func onlyTheAnnouncementPerformsTheCompletionTap() {
        guard SourceTree.isReachable else { return }
        var seen: Set<String> = []
        for file in SourceTree.files() {
            let code = String(file.code)
            switch file.path {
            case "IOS/PhoneTaskCard.swift", "Shared/BoardTaskCard.swift":
                #expect(code.contains("sensoryFeedback(.success") == false,
                        "\(file.path) performs the completion tap from a view the completion removes")
                seen.insert(file.path)
            case "Shared/CompletionFeedback.swift":
                // Both platforms, from the one place that hears about it.
                #expect(code.contains("NSHapticFeedbackManager"))
                #expect(code.contains("notificationOccurred(.success)"),
                        "the announcement no longer taps on iOS, which is where the tick is a finger")
                seen.insert(file.path)
            default:
                break
            }
        }
        #expect(seen.count == 3, "a card or the feedback moved file: found \(seen)")
    }

    // MARK: The presets

    /// Every case of `CompletionSound` has to name a `.caf` actually in the
    /// bundle — `resourceName` and `Resources/Sounds/` are two lists, and this
    /// is what holds them together. `Bundle.main` is the app, because the
    /// suite runs inside the test host — the bargain `PackagingTests` names.
    @Test func everyPresetNamesABundledSound() {
        for sound in CompletionSound.allCases {
            #expect(
                Bundle.main.url(
                    forResource: sound.resourceName, withExtension: "caf", subdirectory: "Sounds"
                ) != nil,
                "\(sound.rawValue) names no bundled sound file"
            )
        }
    }

    /// The picker draws these; two presets sharing a label makes one of them
    /// unchoosable — the claim `everyEnumTheChromeShowsHasADistinctTitle`
    /// makes for the rest of the chrome.
    @Test func everyPresetHasADistinctLabel() {
        let labels = CompletionSound.allCases.map(\.label)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == CompletionSound.allCases.count, "two chimes share a label")
    }
}
