import Foundation
import KanameCore
import PDFKit

/// One reconstructed printed row.
struct PrintedRow {
    let text: String
    /// The words as printed, or `nil` when the page fell back to the text layer's own
    /// newlines: geometry that could not be trusted must not then be reported as if it
    /// could.
    let words: [Word]?
}

/// The printed rows of a page — the one place that decides what a line *is*.
///
/// Extraction's whole difficulty lives here, and nothing else in the app needs to know how
/// it is done: hand it a page, get back the rows a person would see if they held the paper.
enum PrintedRows {
    /// Where a word was printed.
    private struct Placement {
        let xMin: CGFloat
        let xMax: CGFloat
        /// The vertical extent of the word's *ink*. A comma, a capital and an x-height
        /// letter on one row have wildly different midpoints, which is why rows are grouped
        /// by whether extents overlap rather than by how far apart their centres are.
        let yExtent: ClosedRange<CGFloat>
    }

    /// A word that has a position: its own, or the one it was adopted into.
    private struct PlacedWord {
        let text: String
        let range: Range<Int>
        let placement: Placement

        var xMin: CGFloat { placement.xMin }
        var xMax: CGFloat { placement.xMax }
        var yExtent: ClosedRange<CGFloat> { placement.yExtent }
    }

    /// The printed rows of a page.
    ///
    /// The text layer's newlines carry **no authority**: PDFKit reports the breaks *it*
    /// inferred, and on a real statement those are wrong in both directions. It joins
    /// adjacent rows when the leading is tight — a reader handed
    /// `"29/04 … 13,628.36 CR 26/05 … 10.20"` matched one row's date to the other's amount
    /// and imported a single, confidently wrong transaction. And when a document is drawn
    /// column-major — every date, then every description, then every amount — it emits the
    /// page in that order, so no line holds a whole row and a statement reports no spending
    /// at all.
    ///
    /// So rows are re-derived from where the glyphs sit: words are grouped into printed row
    /// bands by vertical overlap, which both splits a merged row and joins a split one, in
    /// one pass.
    ///
    /// A page whose character indices or bounds cannot be trusted falls back — for that
    /// page only — to the text layer's newlines. Fewer breaks is a parse that reads nothing,
    /// which is honest; a wrong break is a number in the wrong row.
    static func of(_ page: PDFPage) -> [PrintedRow] {
        guard let text = page.string else { return [] }
        let units = Array(text.utf16)
        guard page.numberOfCharacters == units.count,
            let placed = Self.place(WordGeometry.words(on: page, units: units))
        else {
            return Self.fallback(text)
        }

        let gutter = 4 * Self.medianSpaceWidth(placed)
        let cap = Self.medianWordHeight(placed).map { 2 * $0 } ?? .greatestFiniteMagnitude

        let rows = Self.bands(placed, cap: cap)
        let boundaries = Self.gutters(placed, atLeast: gutter, uncrossedBy: rows)
        guard !boundaries.isEmpty else { return rows.map(Self.line) }

        return Self.zones(placed, boundaries: boundaries).flatMap { zone in
            Self.bands(zone, cap: cap).map(Self.line)
        }
    }

    /// The text layer's own newlines, for a page whose geometry cannot be trusted. Fewer
    /// breaks is a parse that reads nothing, which is honest; a wrong break is a number in
    /// the wrong row. The page contributes no positions at all rather than untrustworthy
    /// ones.
    private static func fallback(_ text: String) -> [PrintedRow] {
        PDFKitStatementTextExtractor.split(text).map { PrintedRow(text: $0, words: nil) }
    }

    /// Give every word a position, or report that the page has none at all.
    ///
    /// A word whose glyphs reported nothing usable — or nothing usable in one axis, which
    /// happens on its own — is adopted by the nearest word in text order that did, and sits
    /// at that word's right edge on that word's row. It is never dropped: losing a word is
    /// losing part of what a person's statement says, and the neighbour it is printed next
    /// to is the best evidence of where it was.
    private static func place(_ words: [PositionedWord]) -> [PlacedWord]? {
        let hosts = Self.hosts(words)
        var placed: [PlacedWord] = []

        for (index, word) in words.enumerated() {
            let host = hosts[index].map { words[$0] }
            guard let yExtent = word.yExtent ?? host?.yExtent,
                let xRange = word.xRange ?? host?.xRange.map({ $0.upperBound...$0.upperBound })
            else {
                return nil
            }
            placed.append(
                PlacedWord(
                    text: word.text,
                    range: word.range,
                    placement: Placement(xMin: xRange.lowerBound, xMax: xRange.upperBound, yExtent: yExtent)
                )
            )
        }

        return placed.isEmpty ? nil : placed
    }

    /// For each word, the nearest fully-placed word to adopt from: the closest one before it
    /// in text order, or — for a word before any of them — the closest one after.
    private static func hosts(_ words: [PositionedWord]) -> [Int?] {
        var hosts = [Int?](repeating: nil, count: words.count)
        var candidate: Int?
        for index in words.indices {
            if words[index].xRange != nil, words[index].yExtent != nil { candidate = index }
            hosts[index] = candidate
        }
        candidate = nil
        for index in words.indices.reversed() {
            if words[index].xRange != nil, words[index].yExtent != nil { candidate = index }
            if hosts[index] == nil { hosts[index] = candidate }
        }
        return hosts
    }

    /// How wide a space is on this page, taken as the median gap between two words the page
    /// string separates by exactly one separator. Measured rather than assumed, because it
    /// is the unit the gutter test is expressed in and font size varies per document.
    private static func medianSpaceWidth(_ words: [PlacedWord]) -> CGFloat {
        var gaps: [CGFloat] = []
        for (left, right) in zip(words, words.dropFirst()) {
            guard right.range.lowerBound == left.range.upperBound + 1 else { continue }
            let gap = right.xMin - left.xMax
            if gap > 0 { gaps.append(gap) }
        }
        return Self.median(gaps) ?? 0
    }

    private static func medianWordHeight(_ words: [PlacedWord]) -> CGFloat? {
        let heights = words.map { $0.yExtent.upperBound - $0.yExtent.lowerBound }
        guard let median = Self.median(heights), median > 0 else { return nil }
        return median
    }

    /// The middle value, never an average: an average of two floats is arithmetic, and
    /// arithmetic is what makes an output drift between runs (E7).
    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// The page's real vertical separations.
    ///
    /// A *gutter* divides unrelated blocks that happen to share a row band — two side-by-side
    /// panels, or an address block beside a summary box — and banding across one interleaves
    /// them into nonsense rows.
    ///
    /// Being wide is not enough to be one. A transaction table has gaps between its columns
    /// that are every bit as wide and every bit as empty, and on a continuation page — a
    /// ledger's second page, which prints rows and nothing else — they run the full height
    /// of the page. Cutting there would put every amount on a line of its own and re-create
    /// the column-major bug this exists to fix. So a gap is a gutter only if **nothing
    /// printed crosses it**: if any row has words on both sides, it is a column gap, and the
    /// row that spans it is the proof.
    private static func gutters(
        _ words: [PlacedWord],
        atLeast width: CGFloat,
        uncrossedBy rows: [[PlacedWord]]
    ) -> [CGFloat] {
        guard width > 0, words.count > 1 else { return [] }

        let byX = words.sorted { $0.xMin < $1.xMin }
        var candidates: [CGFloat] = []
        var reach = byX[0].xMax
        for word in byX.dropFirst() {
            if word.xMin - reach >= width { candidates.append(word.xMin) }
            reach = max(reach, word.xMax)
        }

        return candidates.filter { boundary in
            !rows.contains { row in
                row.contains { $0.xMin < boundary } && row.contains { $0.xMin >= boundary }
            }
        }
    }

    /// The words either side of each gutter, left to right. A gutter is overlapped by no
    /// word, so every word lies wholly on one side of every boundary: the zones partition
    /// the page's words.
    private static func zones(_ words: [PlacedWord], boundaries: [CGFloat]) -> [[PlacedWord]] {
        var zones = [[PlacedWord]](repeating: [], count: boundaries.count + 1)
        for word in words {
            zones[boundaries.count(where: { word.xMin >= $0 })].append(word)
        }
        return zones.filter { !$0.isEmpty }
    }

    /// The printed rows of one zone, top to bottom.
    ///
    /// Words are swept in printed order — top row first, left to right within it — and each
    /// joins the current row band if its ink overlaps the band's, otherwise it opens the
    /// next. Because the sweep order is a *total* order over values PDFKit returns verbatim,
    /// and the bands come out in the order their first words did, the same file always
    /// reconstructs to the same lines (E7).
    private static func bands(_ zone: [PlacedWord], cap: CGFloat) -> [[PlacedWord]] {
        let sorted = zone.sorted(by: Self.printedOrder)
        var found: [[PlacedWord]] = []
        var current: [PlacedWord] = []
        var extent: ClosedRange<CGFloat>?

        for word in sorted {
            if let band = extent, Self.sharesARow(word.yExtent, band) {
                let grown = Self.union(band, word.yExtent)
                // The cap is what stops FR-006's failure mode: one tall glyph — a bracket, a
                // rule, a logo fragment — otherwise stretches a band until it swallows the
                // row below, and a figure lands in a row it was never printed in.
                if grown.upperBound - grown.lowerBound <= cap {
                    current.append(word)
                    extent = grown
                    continue
                }
            }
            if !current.isEmpty { found.append(current) }
            current = [word]
            extent = word.yExtent
        }
        if !current.isEmpty { found.append(current) }

        return found
    }

    /// Reading order: down the page, then across, with the position in the page string as
    /// the final tiebreak so no two words ever compare equal.
    private static func printedOrder(_ left: PlacedWord, _ right: PlacedWord) -> Bool {
        if left.yExtent.upperBound != right.yExtent.upperBound {
            return left.yExtent.upperBound > right.yExtent.upperBound
        }
        if left.xMin != right.xMin { return left.xMin < right.xMin }
        return left.range.lowerBound < right.range.lowerBound
    }

    /// One band as a line: its words in printed left-to-right order, joined by exactly one
    /// space.
    ///
    /// One space, never zero and never column-proportional padding. Two adjacent column
    /// values must stay separable — every reader's row pattern puts `\s+` between fields —
    /// and padding derived from font metrics would make the output depend on how PDFKit
    /// measures text, which is not stable enough to re-import byte-identically.
    private static func line(_ band: [PlacedWord]) -> PrintedRow {
        let ordered = band.sorted { left, right in
            if left.xMin != right.xMin { return left.xMin < right.xMin }
            return left.range.lowerBound < right.range.lowerBound
        }
        return PrintedRow(
            text: ordered.map(\.text).joined(separator: " "),
            words: ordered.map { Word(text: $0.text, x0: Double($0.xMin), x1: Double($0.xMax)) }
        )
    }

    private static func union(
        _ left: ClosedRange<CGFloat>?,
        _ right: ClosedRange<CGFloat>
    ) -> ClosedRange<CGFloat> {
        guard let left else { return right }
        return Self.union(left, right)
    }

    private static func union(
        _ left: ClosedRange<CGFloat>,
        _ right: ClosedRange<CGFloat>
    ) -> ClosedRange<CGFloat> {
        min(left.lowerBound, right.lowerBound)...max(left.upperBound, right.upperBound)
    }

    /// Does a word sit on the row a band describes? Its ink must overlap the band's by a
    /// real fraction of the shorter of the two — a hyphen or a full stop inside a row's band
    /// does, and the row below, which at worst grazes it by a fraction of a point, does not.
    private static func sharesARow(_ extent: ClosedRange<CGFloat>, _ band: ClosedRange<CGFloat>) -> Bool {
        let overlap = min(extent.upperBound, band.upperBound) - max(extent.lowerBound, band.lowerBound)
        let shorter = min(extent.upperBound - extent.lowerBound, band.upperBound - band.lowerBound)
        return overlap > shorter / 4
    }

}
