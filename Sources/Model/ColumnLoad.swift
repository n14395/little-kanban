import Foundation

/// How full a column is against its WIP limit — the whole of what
/// ``BoardColumn/limit`` does.
///
/// A limit in this app is **advisory**: this type is read by the count pill to
/// pick a colour and by nothing else. There is deliberately no `canAccept` here
/// and no caller that asks one, because refusing a drop punishes the moment
/// somebody is trying to reorganise a full column — see ``BoardColumn/limit``.
///
/// In `Sources/Model/` beside `Priority` and `DueDate` rather than in the store,
/// and compiled into the widget extension for the same reason those are: the
/// theme layer asks it for a chip recipe, and the extension draws the same pill
/// from the digest.
enum ColumnLoad: Hashable, Sendable {
    /// No limit set, which is what every column starts as.
    case unlimited
    case under
    /// Exactly at the limit — the column is full, and still perfectly fine.
    case at
    case over

    /// Whether the pill has anything to say beyond the count. `under` is a
    /// column doing what it is meant to, and colouring it would spend the
    /// reader's attention on the normal case.
    var isWarning: Bool { self == .at || self == .over }

    /// A column's load, from what is in it and what it allows.
    ///
    /// `count` is the number of cards **on the board** — archived ones
    /// excluded. See ``BoardStore/load(ofColumn:)``, which is where that
    /// distinction is made and explained.
    init(count: Int, limit: Int?) {
        guard let limit, limit > 0 else { self = .unlimited; return }
        self = count > limit ? .over : (count == limit ? .at : .under)
    }
}
