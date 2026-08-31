import Foundation
import Testing
@testable import Simple_Kanban

/// The list the board icon picker browses, and the two claims that stand behind
/// every glyph in it: it **shipped**, and it **draws**.
///
/// Both have already been wrong once in this project in the shape the first one
/// takes here — a resource in no target is a file on disk, and the picker built
/// over it is an empty grid with a search field on top. The catalogue is
/// generated (`Tools/make-symbol-catalogue`) rather than typed, so what these
/// guard is the wiring around it rather than anyone's spelling.
@Suite struct SymbolCatalogTests {
    /// The whole of it, read out of the app the tests are hosted in.
    ///
    /// The count is a floor rather than a number: the generator is re-run after
    /// an OS upgrade and a year of new symbols must not fail a test. What a
    /// floor catches is the file arriving empty, truncated, or not at all.
    @Test func theCatalogueIsInTheBundleAndParses() {
        let entries = SymbolCatalog.entries
        #expect(entries.count > 5_000,
                "the catalogue holds \(entries.count) symbols — Resources/SFSymbols.txt is not in the app target")
        #expect(entries.allSatisfy { !$0.name.isEmpty })
        #expect(entries.allSatisfy { !$0.name.hasPrefix("#") }, "a comment line was read as a symbol")
        #expect(Set(entries.map(\.name)).count == entries.count, "a symbol is in the catalogue twice")
    }

    /// **Every name in it draws on this system.** A symbol the running OS has
    /// never heard of is not an error — `Image(systemName:)` renders an empty
    /// frame — so a picker offering one is a picker with holes in it, and the
    /// only way to find out is to ask.
    ///
    /// This is what the generator's deployment-target filter is for; the test
    /// is what says the filter still works.
    @Test func everySymbolOnOfferDrawsOnThisSystem() {
        let blanks = SymbolCatalog.entries.map(\.name).filter { !SymbolMark.exists($0) }
        #expect(blanks.isEmpty, "the picker offers \(blanks.count) glyphs this system cannot draw: \(blanks.prefix(10))")
    }

    /// The suggested sixteen are in the catalogue too, so a board's mark is
    /// findable in All and by search rather than only on the opening screen.
    @Test func theSuggestedMarksAreInTheCatalogue() {
        let names = Set(SymbolCatalog.entries.map(\.name))
        for symbol in Board.startingSymbols {
            #expect(names.contains(symbol), "\(symbol) is offered but is not in the catalogue")
        }
    }

    /// Every group has something in it. An empty one is a menu item that leads
    /// to a blank grid, which is how a category key renamed by an OS release
    /// would show up.
    @Test func everyGroupHoldsSymbols() {
        for category in SymbolCatalog.Category.allCases {
            let entries = SymbolCatalog.entries(in: category)
            #expect(entries.isEmpty == false, "\(category.rawValue) is an empty group")
            #expect(SymbolMark.exists(category.symbol), "\(category.rawValue) has no glyph of its own")
        }
        // The menu names them, so no two may read alike.
        let labels = SymbolCatalog.Category.allCases.map(\.label)
        #expect(Set(labels).count == labels.count, "two groups share a name")
    }

    /// **Search is over the terms as well as the name**, because the name is
    /// often not the word anybody would think of — and dots are spaces, because
    /// nobody types `square.split.2x1` in the order it is spelled.
    @Test func searchFindsASymbolByWhatItIsCalledAndByWhatItIsOf() {
        #expect(SymbolCatalog.search("airplane").contains { $0.name == "airplane" })
        #expect(SymbolCatalog.search("fire").contains { $0.name == "flame" },
                "a system search term did not come through")
        #expect(SymbolCatalog.search("square split").contains { $0.name.hasPrefix("square.split") },
                "the words of a dotted name are not searchable")
        // Case is not a query.
        #expect(SymbolCatalog.search("HOUSE").contains { $0.name == "house" })
        // An empty query is the group, not nothing.
        #expect(SymbolCatalog.search("").count == SymbolCatalog.entries.count)
        #expect(SymbolCatalog.search("qqzzx").isEmpty)
    }

    /// A search inside a group stays in it.
    @Test func aSearchInsideAGroupStaysThere() {
        let inNature = SymbolCatalog.search("leaf", in: .nature)
        #expect(inNature.contains { $0.name == "leaf" })
        #expect(inNature.allSatisfy { $0.categories.contains(.nature) })
    }

    /// The parser, on its own bytes: comments skipped, the two trailing fields
    /// optional, and a line with nothing on it dropped rather than read as a
    /// symbol with no name.
    @Test func theParserIsLenientAboutEverythingButTheName() {
        let parsed = SymbolCatalog.parse(
            """
            # a comment
            house\thome\tdwelling building
            leaf\tnature
            bare

            """
        )
        #expect(parsed.map(\.name) == ["house", "leaf", "bare"])
        #expect(parsed[0].categories == [.home])
        #expect(parsed[0].terms == "dwelling building")
        #expect(parsed[1].terms.isEmpty)
        #expect(parsed[2].categories.isEmpty)
        // A category key this build has never heard of is dropped rather than
        // taking the symbol with it: the file is generated by a newer OS than
        // the one reading it as often as not.
        #expect(SymbolCatalog.parse("flag\tnature,fromthefuture").first?.categories == [.nature])
    }
}
