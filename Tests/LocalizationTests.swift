import Foundation
import Testing
@testable import Simple_Kanban

/// That no user-facing string escapes the catalogue.
///
/// This is the one property in the suite with nothing to observe at runtime: a
/// string that reached the screen without going through `String(localized:)`
/// behaves identically to one that did, right up to the point where somebody
/// runs the app in another language and half of it is still English. So these
/// read the source — see `SourceTree` — and assert about its text.
///
/// The rules are deliberately narrow. `Text("Delete Task")`,
/// `Label("Move Up", systemImage:)` and `Button("Add column")` all take a
/// `LocalizedStringKey`, so their literals *are* extracted and are not
/// violations; a check that flagged them would flag two hundred correct call
/// sites and be turned off within the week. What is checked is the three shapes
/// that genuinely leak: a `String(localized:)` with no comment for the
/// translator, an explicit `Text(verbatim:)` opt-out carrying real words, and
/// prose written as a bare literal in the model and store layers, where there is
/// no `LocalizedStringKey` position for it to be sitting in.
@MainActor
@Suite struct LocalizationTests {
    /// The call heads whose string arguments are on their way into the
    /// catalogue by construction.
    private static let catalogueHeads = [
        #"String\(\s*localized:"#,
        #"AttributedString\(\s*localized:"#,
        #"LocalizedStringResource\("#,
        #"IntentDescription\("#,
        #"TypeDisplayRepresentation\("#,
        #"DisplayRepresentation\("#,
        #"Summary\("#,
        #"Parameter\("#,
        #"AppShortcut\("#,
        #"\bText\("#,
    ]

    /// A literal that is not chrome: `OSLog` output, a `DecodingError`
    /// description, or a literal whose *type* puts it in the catalogue without
    /// a call around it — `static let title: LocalizedStringResource = "Add
    /// Task"` is extracted exactly as `String(localized:)` is.
    private static func isAlreadyAccountedFor(_ file: SourceFile, at offset: Int) -> Bool {
        let line = file.line(containing: offset)
        return line.contains("logger.")
            || line.contains("debugDescription:")
            || line.contains("dialog:")
            || line.contains("systemImage")
            || line.contains("LocalizedStringResource")
            || line.contains("shortTitle:")
            || line.contains("phrases:")
    }

    // MARK: The scan itself

    /// That the source scan found the source.
    ///
    /// Every rule below is "no file breaks this", which a scan that read *no
    /// files* satisfies perfectly. That is not a hypothetical: `files()` strips
    /// `Sources/` off the front of each path so the rules can name directories,
    /// and one unresolved symlink between `#filePath` and the enumerator's URLs
    /// left every path absolute, every directory filter empty, and this whole
    /// suite green over nothing. Mutation testing caught it; this is what stops
    /// it coming back.
    @Test func theScanFindsTheSourceItIsDescribing() {
        guard SourceTree.isReachable else { return }
        let files = SourceTree.files()
        #expect(files.count > 30, "the source scan found \(files.count) files")
        #expect(files.allSatisfy { !$0.path.hasPrefix("/") },
                "a path came out absolute rather than relative to Sources/")
        for directory in ["App/", "Model/", "Store/", "Shared/", "Theme/", "Mac/", "IOS/"] {
            #expect(files.contains { $0.path.hasPrefix(directory) },
                    "nothing was found under \(directory)")
        }
        #expect(files.allSatisfy { !$0.code.isEmpty }, "a file read as empty")
    }

    // MARK: Every catalogue entry has to be translatable

    /// `String(localized:)` without a `comment:` puts a bare English string in
    /// front of a translator with no idea what it labels — "Open" is a verb on a
    /// button and an adjective on a status line, and they are different words in
    /// most languages.
    ///
    /// Flat zero. It was a ratchet at nine while 7.2 was landing beside it; the
    /// nine were all `accessibilityRepresentation` buttons and they now carry
    /// comments, so the rule says what it always meant to.
    @Test func everyLocalizedStringCarriesATranslatorComment() {
        guard SourceTree.isReachable else { return }
        var missing: [String] = []
        for file in SourceTree.files() {
            for call in file.calls(headed: #"String\(\s*localized:"#) where !call.text.contains("comment:") {
                missing.append("\(file.path):\(file.line(of: call.offset))")
            }
        }
        #expect(missing.isEmpty,
                "\(missing.count) String(localized:) calls have no translator comment: \(missing)")
    }

    /// One localisation API, so one extraction path. `NSLocalizedString` reads
    /// a `.strings` table this app does not ship and would silently return its
    /// own key.
    @Test func nothingReachesForTheOlderLocalizationAPI() {
        guard SourceTree.isReachable else { return }
        var found: [String] = []
        for file in SourceTree.files() {
            for call in file.calls(headed: #"NSLocalizedString\("#) {
                found.append("\(file.path):\(file.line(of: call.offset))")
            }
        }
        #expect(found.isEmpty, "NSLocalizedString is used at \(found)")
    }

    // MARK: The explicit opt-out

    /// `Text(verbatim:)` is the one call that says "do not translate this". Every
    /// use of it must be a value — a count, a glyph, text already rendered
    /// through the catalogue — and never words typed into the call.
    ///
    /// Flat zero. There is no case for a bare English literal behind a call
    /// whose whole purpose is to keep it out of the catalogue.
    @Test func verbatimTextIsNeverABareLiteral() {
        guard SourceTree.isReachable else { return }
        var offenders: [String] = []
        for file in SourceTree.files() {
            for call in file.calls(headed: #"Text\(\s*verbatim:"#) {
                // A value is fine — `Text(verbatim: glyph)`, or a literal that
                // is nothing but an interpolation or an escape, "\(count)" and
                // "\u{2303}". Typed words are not.
                guard call.text.contains("\"") else { continue }
                guard !call.text.contains("\\(") && !call.text.contains("\\u{") else { continue }
                offenders.append("\(file.path):\(file.line(of: call.offset)) — \(call.text)")
            }
        }
        #expect(offenders.isEmpty, "Text(verbatim:) carries untranslatable words at \(offenders)")
    }

    // MARK: Prose below the view layer

    /// The model and the store have no `LocalizedStringKey` positions, so a
    /// sentence written as a bare literal there is a sentence nobody will ever
    /// translate. Everything they do show the user goes through
    /// `String(localized:)` or a `LocalizedStringResource`.
    ///
    /// Two literals are allowed, and only two: the sample board's name, which
    /// `SeedData` writes and the v4 → v5 migration has to write again for a file
    /// that predates boards. That is board *data* — a name the user can rename —
    /// rather than chrome, and `SeedData` says so where it is declared.
    @Test func theModelAndTheStoreCarryNoUnlocalisedProse() {
        guard SourceTree.isReachable else { return }
        let allowed: Set<String> = ["Model/SeedData.swift", "Store/BoardMigration.swift"]
        var offenders: [String] = []
        var scanned = 0
        for file in SourceTree.files()
        where file.path.hasPrefix("Model/") || file.path.hasPrefix("Store/") {
            scanned += 1
            let spans = file.spans(headedByAnyOf: Self.catalogueHeads)
            for literal in file.stringLiterals() {
                let words = literal.contents
                guard let first = words.first, first.isUppercase, words.contains(" ") else { continue }
                // Identifiers, key paths and format templates are not prose.
                guard !words.contains("/"), !words.contains("_"), !words.contains("{") else { continue }
                guard !spans.contains(where: { $0.contains(literal.offset) }) else { continue }
                guard !Self.isAlreadyAccountedFor(file, at: literal.offset) else { continue }
                if allowed.contains(file.path), words == SeedData.defaultBoard.name { continue }
                offenders.append("\(file.path):\(file.line(of: literal.offset)) — \(words)")
            }
        }
        #expect(scanned >= 10, "only \(scanned) files were scanned below the view layer")
        #expect(offenders.isEmpty, "prose written as a bare literal below the view layer: \(offenders)")
    }

    // MARK: What the build actually shipped

    /// The compiled table, read out of the app the tests are hosted in.
    ///
    /// `Localizable.xcstrings` is a source file: it reaches the screen only if
    /// it is in the target, and Xcode compiles it to `en.lproj/Localizable.strings`
    /// only for keys whose source value is filled in. Both have already been
    /// wrong once — the catalogue sat outside every target for a while, and
    /// every `String(localized:)` in the app quietly returned its own key.
    private func compiledTable() throws -> [String: String] {
        let url = try #require(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"),
            "en.lproj/Localizable.strings is not in the built bundle — the catalogue is in no target"
        )
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    @Test func theCatalogueIsCompiledIntoTheApp() throws {
        let table = try compiledTable()
        #expect(table.count > 400, "the shipped table has only \(table.count) strings in it")
    }

    /// Chrome that reaches `Text` through a helper rather than as a literal in
    /// the call.
    ///
    /// This is the one property no source scan can state: the two spellings look
    /// identical on screen and differ only in whether the compiler extracted
    /// anything, so nothing goes wrong until the app is run in another language
    /// and these particular words are still English. Seven view helpers took
    /// their title as `String` — which is a finished string, never a key — and
    /// these are the words that leaked. A helper reverted to `String` fails
    /// here.
    ///
    /// It follows that a string added to the interface and not synced into the
    /// catalogue fails too, which is the intended reading of `README`'s
    /// **Language and direction**: the sync is part of the change.
    @Test func theStringsShownThroughViewHelpersAreInTheTable() throws {
        let table = try compiledTable()
        let throughAHelper = [
            "Boards", "Views", "Labels", "Reminders",   // sidebar and drawer section headings
            "Name", "Short",                            // the column editors, both platforms
            "Due", "Priority",                          // inspector field names, phone attribute cards
            "Previous column", "Next column",           // the phone pager's arrows
            "Move Up", "Move Down",                     // the drawer's column stepper
            "No due date",                              // the due chip's spoken value
        ]
        for key in throughAHelper {
            #expect(table[key] == key, "“\(key)” never reached the catalogue")
        }
    }

    // MARK: What the catalogue has to be able to render

    /// Every activity kind renders to a sentence rather than to a case name or
    /// an empty string. The feed is the surface where a missed `String(localized:)`
    /// hides longest — an entry written months ago is not looked at again.
    @Test func everyActivityKindRendersASentence() {
        let today = CalendarDay(year: 2026, month: 8, day: 20)
        for kind in TestBoard.everyActivityKind {
            let entry = ActivityEntry(kind, when: TestBoard.epoch)
            let text = entry.text(today: today)
            #expect(!text.isEmpty, "\(kind) renders nothing")
            #expect(!text.contains("("), "\(kind) renders a case name rather than a sentence: \(text)")
            #expect(text.first?.isUppercase == true || text.first?.isNumber == true,
                    "\(kind) renders \(text)")
        }
    }

    /// And every enum the chrome shows has a distinct, non-empty title, so a
    /// translator has something to translate and a user something to tell apart.
    @Test func everyEnumTheChromeShowsHasADistinctTitle() {
        let viewTitles = SavedView.allCases.map(\.label)
        #expect(viewTitles.allSatisfy { !$0.isEmpty })
        #expect(Set(viewTitles).count == SavedView.allCases.count, "two saved views share a title")

        let orderLabels = BoardSortOrder.allCases.map(\.label)
        #expect(orderLabels.allSatisfy { !$0.isEmpty })
        #expect(Set(orderLabels).count == BoardSortOrder.allCases.count, "two sort orders share a label")

        let priorities = Priority.allCases.map(\.displayName)
        #expect(priorities.allSatisfy { !$0.isEmpty })
        #expect(Set(priorities).count == Priority.allCases.count, "two priorities share a name")
    }
}
