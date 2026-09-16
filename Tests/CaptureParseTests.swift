import Foundation
import Testing
@testable import LittleKanban

/// The grammar a typed title is read with, and the two rules that stop it
/// eating words nobody offered it: a sigil is consent, and a date has to be at
/// the end of the line.
///
/// Everything here names its own day and its own calendar. "Next friday" is
/// only a testable claim once the Wednesday it was typed on is written down.
@Suite struct CaptureParseTests {
    /// Wednesday, 2 September 2026 — asserted below rather than assumed, so a
    /// mistake in this constant fails loudly instead of quietly re-basing every
    /// weekday expectation in the suite.
    static let wednesday = CalendarDay(year: 2026, month: 9, day: 2)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    static func read(
        _ line: String, on today: CalendarDay = wednesday, rejecting rejected: Set<String> = []
    ) -> CaptureParse {
        CaptureParse.parse(
            line, labels: LabelDef.seed, today: today, calendar: calendar, rejecting: rejected
        )
    }

    @Test func theFixtureIsTheWednesdayItSaysItIs() {
        let weekday = Self.calendar.component(.weekday, from: Self.wednesday.date(in: Self.calendar))
        #expect(weekday == 4, "the suite's anchor day must be a Wednesday for its weekday maths to mean anything")
    }

    // MARK: Leaving the line alone

    @Test func aPlainLineIsUntouched() {
        let parse = Self.read("Ship the beta")
        #expect(parse.isPlain)
        #expect(parse.title == "Ship the beta")
        #expect(parse.due == nil)
        #expect(parse.priority == nil)
        #expect(parse.labelKeys.isEmpty)
    }

    /// The whitespace a plain line was typed with survives, because nothing was
    /// removed from it and rebuilding it would collapse runs of spaces the user
    /// put there. Only a line something was taken out of gets rebuilt.
    @Test func aPlainLineKeepsItsOwnSpacing() {
        #expect(Self.read("Ship  the   beta").title == "Ship  the   beta")
    }

    /// A line of nothing but tokens would otherwise mint an untitled card
    /// wearing a label — and an untitled card is quick capture's own thing.
    @Test func aLineOfNothingButTokensIsLeftAlone() {
        let parse = Self.read("#bug !high")
        #expect(parse.isPlain)
        #expect(parse.title == "#bug !high")
    }

    // MARK: The sigils

    @Test func theSigilsAreReadAnywhereInTheLine() {
        let parse = Self.read("!high Fix the #bug crash")
        #expect(parse.title == "Fix the crash")
        #expect(parse.priority == .high)
        #expect(parse.labelKeys == ["bug"])
    }

    @Test func aPriorityAnswersToItsTokenAndToItsName() {
        for spelling in ["!max", "!Max", "!MAX"] {
            #expect(Self.read("Rewrite the parser \(spelling)").priority == .max, "\(spelling)")
        }
    }

    @Test func trailingPunctuationDoesNotBreakAToken() {
        let parse = Self.read("Fix the crash #bug.")
        #expect(parse.labelKeys == ["bug"])
        #expect(parse.title == "Fix the crash")
    }

    /// The same sigil twice is two tokens with two identities. Identified by
    /// their text alone, "fix the #bug crash #bug" handed the preview's
    /// `ForEach` two rows under one id — and one label, which is right, so
    /// only the identities were wrong.
    @Test func theSameSigilTwiceIsTwoTokensThatCanBeToldApart() {
        let parse = Self.read("fix the #bug crash #bug")
        #expect(parse.taken.count == 2)
        #expect(Set(parse.taken.map(\.id)).count == 2, "two chips under one identity")
        #expect(parse.labelKeys == ["bug"], "one spelling twice is still one label")
        #expect(parse.title == "fix the crash")
    }

    /// A hyphen is what `LabelDef.key(from:)` puts *inside* a slug, so it must
    /// survive the punctuation trim that removes the full stop above.
    @Test func aHyphenatedLabelIsOneLabel() {
        let labels = LabelDef.seed + [LabelDef(key: "infra-work", name: "Infra Work",
                                               light: LabelTone.inkPair.light,
                                               dark: LabelTone.inkPair.dark)]
        let parse = CaptureParse.parse("Move the runners #infra-work", labels: labels,
                                       today: Self.wednesday, calendar: Self.calendar)
        #expect(parse.labelKeys == ["infra-work"])
    }

    /// A name the board does not have yet is one it is about to have: `#` is
    /// somebody naming a label, and leaving the word in the title said nothing
    /// and offered no way to find out why. The chip is what keeps that from
    /// being silent — see `CapturePreview`.
    @Test func anUnknownLabelIsANewLabel() {
        let parse = Self.read("Fix the crash #nonsense")
        #expect(parse.title == "Fix the crash")
        #expect(parse.labelKeys == ["nonsense"])
        #expect(parse.newLabels.map(\.key) == ["nonsense"])
    }

    /// The key is the slug; the *name* is the spelling it was typed in, because
    /// that is what the chip and the label manager will show.
    @Test func aNewLabelKeepsTheSpellingItWasTypedIn() {
        let parse = Self.read("Draft the post #Roadmap")
        #expect(parse.labelKeys == ["roadmap"])
        #expect(parse.newLabels.map(\.name) == ["Roadmap"])
    }

    /// One label named twice is one new label, not two rows in the vocabulary.
    @Test func theSameNewLabelTwiceIsOneNewLabel() {
        #expect(Self.read("Fix the #nonsense crash #Nonsense").newLabels.map(\.key) == ["nonsense"])
    }

    /// The one shape that must never mint: a payload with nothing alphanumeric
    /// in it slugs to a fresh unique key — see `LabelDef.key(from:)` — so it
    /// would make a label nobody could ever type a second time.
    @Test func aPayloadOfPunctuationIsNotALabel() {
        #expect(Self.read("Write up the #-- keys").isPlain)
    }

    /// The seed's key is `ios` and its name is "iOS". Every spelling of it
    /// lands on that one label rather than minting a second one beside it —
    /// which is what makes `LabelDef.key(from:)` the thing both ends are
    /// compared through.
    @Test func aLabelIsFoundInAnyCase() {
        for spelling in ["#ios", "#iOS", "#IOS"] {
            let parse = Self.read("Check the sheet \(spelling)")
            #expect(parse.labelKeys == ["ios"], "\(spelling)")
            #expect(parse.newLabels.isEmpty, "\(spelling) minted a label beside iOS")
            #expect(parse.taken.first?.meaning == .label(key: "ios", name: "iOS", isNew: false),
                    "\(spelling) should wear the label's own name")
        }
    }

    /// A key that arrived in an imported board file need not be a slug already,
    /// so the *board's* key is slugged before it is compared as well.
    @Test func aStoredKeyThatIsNotASlugIsStillFound() {
        let labels = [LabelDef(key: "Infra-Work", name: "Something Else",
                               light: LabelTone.inkPair.light, dark: LabelTone.inkPair.dark)]
        let parse = CaptureParse.parse("Move the runners #infra-work", labels: labels,
                                       today: Self.wednesday, calendar: Self.calendar)
        #expect(parse.labelKeys == ["Infra-Work"], "the label's own key is what a task stores")
        #expect(parse.newLabels.isEmpty)
    }

    @Test func aHashFollowedByADigitIsARankNotALabel() {
        #expect(Self.read("#1 rewrite the parser").isPlain)
    }

    @Test func theSameLabelTwiceIsOneLabel() {
        #expect(Self.read("Fix the #bug crash #bug").labelKeys == ["bug"])
    }

    @Test func tokensComeBackInWrittenOrder() {
        let parse = Self.read("#bug Fix the crash !high tomorrow")
        let kinds = parse.taken.map(\.text)
        #expect(kinds == ["#bug", "!high", "tomorrow"])
    }

    // MARK: The date, and only at the end

    @Test func aDayNameInTheMiddleOfASentenceIsJustAWord() {
        let parse = Self.read("Call Friday about the invoice")
        #expect(parse.isPlain, "a date mid-sentence is the false positive the trailing rule exists to stop")
    }

    @Test func aDayNameAtTheEndIsADate() {
        let parse = Self.read("Call about the invoice friday")
        #expect(parse.title == "Call about the invoice")
        #expect(parse.due == Self.wednesday.adding(days: 2), "Wednesday to Friday is two days")
    }

    /// The sigils are stripped before the tail is looked at, so a date is still
    /// trailing with a `!high` written after it.
    @Test func aDateIsStillTrailingWithASigilBehindIt() {
        #expect(Self.read("Call about the invoice friday !high").due == Self.wednesday.adding(days: 2))
    }

    @Test func todayAndTomorrow() {
        #expect(Self.read("Post the notes today").due == Self.wednesday)
        #expect(Self.read("Post the notes tomorrow").due == Self.wednesday.adding(days: 1))
    }

    @Test func nextWeekIsSevenDays() {
        let parse = Self.read("Review the draft next week")
        #expect(parse.due == Self.wednesday.adding(days: 7))
        #expect(parse.title == "Review the draft")
    }

    /// "Friday" on a Friday means the one coming, not the one you are standing
    /// in — otherwise the grammar quietly means "today" one day in seven.
    @Test func askingForTodaysOwnWeekdayMeansTheOneComing() {
        let friday = Self.wednesday.adding(days: 2)
        #expect(Self.read("Send the invoice friday", on: friday).due == friday.adding(days: 7))
    }

    /// English does not agree with itself about "next friday". The grammar
    /// picks the reading that makes "next" mean something, and the preview
    /// names the day it landed on.
    @Test func nextIsAWeekPastTheOneComing() {
        #expect(Self.read("Ship it friday").due == Self.wednesday.adding(days: 2))
        #expect(Self.read("Ship it next friday").due == Self.wednesday.adding(days: 9))
    }

    @Test func thisAndOnBothMeanTheOneComing() {
        #expect(Self.read("Ship it this friday").due == Self.wednesday.adding(days: 2))
        #expect(Self.read("Ship it on friday").due == Self.wednesday.adding(days: 2))
    }

    /// The longest trailing phrase wins, or "next friday" would be read as the
    /// "friday" inside it.
    @Test func theLongestPhraseWins() {
        let parse = Self.read("Ship it next friday")
        #expect(parse.taken.count == 1)
        #expect(parse.taken.first?.text == "next friday")
        #expect(parse.title == "Ship it")
    }

    @Test func countedDaysAndWeeks() {
        #expect(Self.read("Chase it in 3 days").due == Self.wednesday.adding(days: 3))
        #expect(Self.read("Chase it in 2 weeks").due == Self.wednesday.adding(days: 14))
        #expect(Self.read("Chase it in 1 day").due == Self.wednesday.adding(days: 1))
    }

    @Test func aCountOfNoneIsNotADate() {
        #expect(Self.read("Chase it in 0 days").isPlain)
    }

    @Test func aDayAndAMonthEitherWayRound() {
        let october = CalendarDay(year: 2026, month: 10, day: 12)
        #expect(Self.read("File the return 12 oct").due == october)
        #expect(Self.read("File the return oct 12").due == october)
        #expect(Self.read("File the return 12 october").due == october)
    }

    /// A day already gone this year means next year's — nobody types a due date
    /// into the past.
    @Test func aMonthAlreadyPastRollsRoundToNextYear() {
        #expect(Self.read("File the return 12 jan").due == CalendarDay(year: 2027, month: 1, day: 12))
    }

    /// `CalendarDay` resolves 31 February to 3 March, which is the right answer
    /// for a value in hand and the wrong one for a thing somebody typed.
    @Test func anImpossibleDateIsATypoRatherThanAnAdjustment() {
        #expect(Self.read("File the return 31 feb").isPlain)
        #expect(Self.read("File the return 2026-02-31").isPlain)
    }

    @Test func isoIsTheOneNumericFormAccepted() {
        #expect(Self.read("File the return 2026-03-12").due == CalendarDay(year: 2026, month: 3, day: 12))
        // March in half the world, December in the other half.
        #expect(Self.read("File the return 12/03/2026").isPlain)
    }

    // MARK: Handing a token back

    @Test func aRefusedTokenStaysInTheTitle() {
        let parse = Self.read("Fix the crash #bug", rejecting: ["#bug"])
        #expect(parse.isPlain)
        #expect(parse.title == "Fix the crash #bug")
    }

    /// Refusals are folded, so refusing `#Bug` keeps refusing it when it is
    /// retyped in another case.
    @Test func aRefusalSurvivesBeingRetypedDifferently() {
        let parse = Self.read("Fix the crash #Bug", rejecting: [CaptureParse.fold("#bug")])
        #expect(parse.isPlain)
    }

    @Test func refusingOneTokenLeavesTheOthersStanding() {
        let parse = Self.read("Fix the crash #bug !high", rejecting: [CaptureParse.fold("#bug")])
        #expect(parse.priority == .high)
        #expect(parse.labelKeys.isEmpty)
        #expect(parse.title == "Fix the crash #bug")
    }

    /// Refusing the date puts its words back where they were, which for a
    /// trailing phrase is the end of the title.
    @Test func refusingADateGivesItsWordsBack() {
        let parse = Self.read("Ship it next friday", rejecting: [CaptureParse.fold("next friday")])
        #expect(parse.isPlain)
        #expect(parse.title == "Ship it next friday")
    }

    // MARK: Empty and odd input

    @Test func nothingAtAllIsNothing() {
        #expect(Self.read("").isPlain)
        #expect(Self.read("   ").title.isEmpty)
    }

    @Test func aBareSigilIsNotAToken() {
        #expect(Self.read("Write up the # and the ! keys").isPlain)
    }
}

/// What the grammar does once it reaches the board: one card, wearing what was
/// read, at the cost of exactly one ⌘Z.
@Suite @MainActor struct CaptureCommitTests {
    private func composing(_ line: String) -> (store: BoardStore, undo: RecordingUndoManager) {
        let pair = TestBoard.undoing()
        pair.store.beginAddingWhereVisible()
        pair.store.draft = line
        return pair
    }

    @Test func theCardIsMintedWearingWhatWasRead() throws {
        let (store, _) = composing("Fix the crash #bug !high tomorrow")
        let id = try #require(store.commitDraft())
        let task = try #require(store[id])
        #expect(task.title == "Fix the crash")
        #expect(task.priority == .high)
        #expect(task.labelKeys == ["bug"])
        #expect(task.due == CalendarDay(.now).adding(days: 1))
    }

    /// The whole reason the readings are passed into `mintTask` rather than set
    /// afterwards: four mutators would be four steps, and one ⏎ would cost four
    /// ⌘Z to take back.
    @Test func aReadLineCostsExactlyOneUndoStep() throws {
        let (store, undo) = composing("Fix the crash #bug !high tomorrow")
        step(undo) { store.commitDraft() }
        #expect(undo.actionNames == ["New Task"])
        undo.undo()
        #expect(store.tasks.allSatisfy { $0.title != "Fix the crash" }, "one ⌘Z should take the whole card back")
    }

    /// A card born with a due date logs `.created` and nothing else — the feed
    /// is for things that happened *to* a card, and this is how it arrived.
    @Test func arrivingWithADateIsNotAnEventInTheFeed() throws {
        let (store, _) = composing("Fix the crash !high tomorrow")
        let id = try #require(store.commitDraft())
        let task = try #require(store[id])
        #expect(task.activity.count == 1)
        #expect(task.activity.first?.kind == .created)
    }

    @Test func theSwitchOffLeavesTheLineExactlyAsTyped() throws {
        let (store, _) = composing("Fix the crash #bug !high tomorrow")
        store.interpretsCapture = false
        let id = try #require(store.commitDraft())
        let task = try #require(store[id])
        #expect(task.title == "Fix the crash #bug !high tomorrow")
        #expect(task.priority == .default)
        #expect(task.labelKeys.isEmpty)
    }

    @Test func aRefusedTokenReachesTheCardAsText() throws {
        let (store, _) = composing("Fix the crash #bug")
        let token = try #require(store.draftParse.taken.first)
        store.rejectFromDraft(token)
        let id = try #require(store.commitDraft())
        let task = try #require(store[id])
        #expect(task.title == "Fix the crash #bug")
        #expect(task.labelKeys.isEmpty)
    }

    /// Refusals belong to the line they were made about. Left standing, the
    /// next card typed into the same composer would silently inherit them.
    @Test func refusalsDoNotOutliveTheirDraft() throws {
        let (store, _) = composing("Fix the crash #bug")
        store.rejectFromDraft(try #require(store.draftParse.taken.first))
        store.commitDraft()
        #expect(store.draftRejections.isEmpty)

        store.beginAddingWhereVisible()
        store.draft = "Fix the other crash #bug"
        #expect(store.draftParse.labelKeys == ["bug"], "a new line starts with nothing refused")
    }

    @Test func cancellingAlsoClearsThem() throws {
        let (store, _) = composing("Fix the crash #bug")
        store.rejectFromDraft(try #require(store.draftParse.taken.first))
        store.cancelDraft()
        #expect(store.draftRejections.isEmpty)
    }

    /// A name the board has never seen joins its vocabulary rather than being
    /// left in the title, wearing the spelling it was typed in.
    @Test func anUnknownLabelIsMintedWithTheCard() throws {
        let (store, _) = composing("Draft the post #Roadmap")
        let id = try #require(store.commitDraft())
        let task = try #require(store[id])
        #expect(task.title == "Draft the post")
        #expect(task.labelKeys == ["roadmap"])
        #expect(store.label(forKey: "roadmap")?.name == "Roadmap")
    }

    /// And it costs one ⌘Z, which takes the definition back with the card: a
    /// colour left in the vocabulary for a card that no longer exists is what
    /// minting it inside the step avoids.
    @Test func aMintedLabelGoesBackWithItsCard() throws {
        let (store, undo) = composing("Draft the post #roadmap")
        step(undo) { store.commitDraft() }
        #expect(undo.actionNames == ["New Task"])
        undo.undo()
        #expect(store.label(forKey: "roadmap") == nil, "one ⌘Z left the label behind")
    }

    /// `#ios` is the seed called "iOS", not a second label beside it — the case
    /// somebody types a name in is never the difference between wearing a label
    /// and making one.
    @Test func aLabelTypedInAnotherCaseIsTheSameLabel() throws {
        let (store, _) = composing("Check the sheet #ios")
        let before = store.labels.count
        let id = try #require(store.commitDraft())
        #expect(store[id]?.labelKeys == ["ios"])
        #expect(store.labels.count == before, "#ios minted a second label beside iOS")
        #expect(store.label(forKey: "ios")?.name == "iOS")
    }

    /// The switch off is the switch off: no card wears a label and no label is
    /// made, whatever the line says.
    @Test func theSwitchOffMintsNothingEither() throws {
        let (store, _) = composing("Draft the post #roadmap")
        store.interpretsCapture = false
        let id = try #require(store.commitDraft())
        #expect(store[id]?.title == "Draft the post #roadmap")
        #expect(store.label(forKey: "roadmap") == nil)
    }

    /// Handing the chip back keeps the words in the title *and* leaves the
    /// board's vocabulary alone, which is the half a new label adds to the
    /// escape hatch.
    @Test func aRefusedNewLabelIsNeverMade() throws {
        let (store, _) = composing("Draft the post #roadmap")
        store.rejectFromDraft(try #require(store.draftParse.taken.first))
        let id = try #require(store.commitDraft())
        #expect(store[id]?.title == "Draft the post #roadmap")
        #expect(store.label(forKey: "roadmap") == nil)
    }

    /// The line is re-read at the ⏎ against the labels the board has *then*, so
    /// a label deleted while the composer is open is read as a new one from
    /// that moment — the chip under the field changes with it, which is the
    /// user seeing the same thing the mint is about to do. The alternative is a
    /// `#bug` that silently means nothing because of something that happened in
    /// another window.
    @Test func aLabelDeletedMidDraftIsReadAsANewOne() throws {
        let (store, _) = composing("Fix the crash #bug")
        #expect(store.draftParse.newLabels.isEmpty, "the seed's Bug is not a new label")
        store.deleteLabel("bug")
        #expect(store.draftParse.newLabels.map(\.key) == ["bug"])

        let id = try #require(store.commitDraft())
        #expect(store[id]?.labelKeys == ["bug"])
        #expect(store.label(forKey: "bug")?.name == "bug", "the card wears a definition that exists")
    }
}
