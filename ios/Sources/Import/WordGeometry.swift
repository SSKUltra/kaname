import Foundation
import PDFKit

/// A word of a page's text, and where it was printed as far as that could be established.
///
/// Horizontal and vertical position are separately optional because PDFKit loses them
/// separately.
struct PositionedWord {
    let text: String
    /// The word's UTF-16 range in the page string.
    let range: Range<Int>
    let xRange: ClosedRange<CGFloat>?
    let yExtent: ClosedRange<CGFloat>?
}

/// Where the words of a page were printed.
///
/// This is the only place that knows how PDFKit reports geometry, and it exists because
/// getting a word's position out of PDFKit is not the one-line matter it appears to be.
///
/// **The indices do not line up.** `characterBounds(at:)` is indexed over the page's
/// *glyphs*, while `string` additionally carries the line breaks PDFKit **inserted** between
/// the runs it decided were separate lines. Those breaks stand for no glyph, so a word's
/// glyphs sit as many places earlier in `characterBounds` as there are breaks before it.
/// Uncorrected, every word after the first line reports some other word's position — and the
/// drift grows down the page. On a column-major statement, where the text layer emits one
/// short line per printed *cell*, the drift reaches tens of characters within a few rows and
/// a row's date is read at another row's amount. Correcting for it is what makes the rest of
/// this work at all.
///
/// **Some glyph rects are nonsense.** PDFKit hands back a stray, far-off rect for the last
/// glyph or two of a drawn run — hundreds of points wide, or attributed to the row below.
/// So a word's row is the row *most* of its glyphs agree on, not the union of all of them:
/// one stray rect would otherwise give a word an extent spanning two printed rows and the
/// row below would be swallowed whole.
///
/// **The fallback is right but blunt.** `PDFSelection.bounds(for:)` resolves a range of the
/// page string through the text layer itself, so it needs no index correction — but it is no
/// finer than the line PDFKit thinks the range belongs to, and on a tightly-led statement it
/// thinks two printed rows are one line: every word of both rows then reports the same
/// doubled box, and on such a line it misplaces a word horizontally too. So it is what a
/// word falls back to, never what it prefers: per glyph when the glyphs can be trusted, per
/// line when they cannot. A page whose indices cannot be reconciled at all reads too little,
/// which is honest, rather than reading a figure into a row it was never printed in.
enum WordGeometry {
    /// How far apart the two APIs may typically place a word and still be describing the
    /// same one. A page whose glyph indices do not line up misplaces a word by whole words —
    /// tens of points within a couple of rows, and worse further down — so a threshold of
    /// about one character separates the two cases with room to spare.
    private static let agreementTolerance: CGFloat = 6

    /// A word's ink: the row its glyphs agree on, and how far it reaches across the page.
    private struct Ink {
        let rows: ClosedRange<CGFloat>
        /// `nil` when every glyph on that row came back an implausible width, which is one
        /// of the two ways PDFKit corrupts a run's last glyphs.
        let xRange: ClosedRange<CGFloat>?
    }

    static func words(on page: PDFPage, units: [UInt16]) -> [PositionedWord] {
        var ranges: [Range<Int>] = []
        var index = 0
        while index < units.count {
            guard !isSeparator(units[index]) else {
                index += 1
                continue
            }
            let end = Self.endOfWord(units, from: index)
            ranges.append(index..<end)
            index = end
        }

        let breaks = Self.lineBreaksBefore(units)
        let glyphs = Self.glyphBounds(on: page, count: units.count - (breaks.last ?? 0))
        let widthCap = Self.median(glyphs.compactMap { $0?.width }).map { 4 * $0 } ?? .greatestFiniteMagnitude
        let boxes = ranges.map { Self.box(of: $0, on: page) }
        let ink = ranges.map { Self.ink(of: $0, shiftedBy: breaks[$0.lowerBound], glyphs: glyphs, widthCap: widthCap) }
        let believeInk = Self.agree(boxes, ink)

        return ranges.enumerated().map { position, range in
            let box = boxes[position]
            let ink = believeInk ? ink[position] : nil
            return PositionedWord(
                text: String(decoding: units[range], as: UTF16.self),
                range: range,
                xRange: ink?.xRange ?? box.map { $0.minX...max($0.minX, $0.maxX) },
                yExtent: ink?.rows ?? box.map { $0.minY...$0.maxY }
            )
        }
    }

    /// Every glyph's bounds, asked for exactly once.
    ///
    /// `characterBounds(at:)` is the dominant cost of extraction, so it is called once per
    /// glyph of the page and never again — everything downstream reads this array.
    private static func glyphBounds(on page: PDFPage, count: Int) -> [CGRect?] {
        var bounds = [CGRect?](repeating: nil, count: max(0, count))
        for index in bounds.indices where index < page.numberOfCharacters {
            let rect = page.characterBounds(at: index)
            if Self.isUsable(rect) { bounds[index] = rect }
        }
        return bounds
    }

    /// How many line breaks precede each index of the page string.
    ///
    /// PDFKit *inserts* the breaks between the runs it decided are separate lines, and they
    /// occupy an index in `string` while standing for no glyph — so a word's glyphs sit that
    /// many places earlier in `characterBounds`'s own indexing.
    private static func lineBreaksBefore(_ units: [UInt16]) -> [Int] {
        var counts = [Int](repeating: 0, count: units.count + 1)
        for index in units.indices {
            counts[index + 1] = counts[index] + (units[index] == newline ? 1 : 0)
        }
        return counts
    }

    /// A word's ink, as the glyphs at its indices report it.
    ///
    /// PDFKit hands back a stray rect for the last glyph or two of a drawn run — attributed
    /// to the row below, or hundreds of points wide. So a word is placed by consensus: its
    /// row is the row most of its glyphs agree on, an even split going to the earlier one
    /// (the corruption is at the *end* of a run), and it reaches only as far as the glyphs
    /// on that row that are the width of a glyph. Unioning the strays in instead would give
    /// a word an extent spanning two printed rows and half the page.
    private static func ink(
        of range: Range<Int>,
        shiftedBy breaks: Int,
        glyphs: [CGRect?],
        widthCap: CGFloat
    ) -> Ink? {
        let start = range.lowerBound - breaks
        let end = range.upperBound - breaks
        guard start >= 0, end <= glyphs.count else { return nil }
        let rects = (start..<end).compactMap { glyphs[$0] }

        var clusters: [(extent: ClosedRange<CGFloat>, count: Int)] = []
        for rect in rects {
            let extent = rect.minY...rect.maxY
            if let found = clusters.firstIndex(where: { Self.overlaps(extent, $0.extent) }) {
                clusters[found] = (Self.union(clusters[found].extent, extent), clusters[found].count + 1)
            } else {
                clusters.append((extent, 1))
            }
        }

        var row: ClosedRange<CGFloat>?
        var best = 0
        for cluster in clusters where cluster.count > best {
            row = cluster.extent
            best = cluster.count
        }
        guard let row else { return nil }

        let onRow = rects.filter { Self.overlaps($0.minY...$0.maxY, row) && $0.width <= widthCap }
        let xRange = onRow.map { $0.minX...max($0.minX, $0.maxX) }
            .reduce(into: ClosedRange<CGFloat>?.none) { span, next in
                span = span.map { Self.union($0, next) } ?? next
            }
        return Ink(rows: row, xRange: xRange)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// The line box PDFKit reports for a word's own range.
    private static func box(of range: Range<Int>, on page: PDFPage) -> CGRect? {
        let selection = page.selection(for: NSRange(location: range.lowerBound, length: range.count))
        guard let box = selection?.bounds(for: page), Self.isUsable(box) else { return nil }
        return box
    }

    /// A word's ink, as the glyphs at its indices report it.
    ///
    /// PDFKit hands back a stray, far-off rect for the last glyph or two of a drawn run, so
    /// a word is placed by consensus: its row is the row most of its glyphs agree on, and an
    /// even split goes to the earlier one — the corruption is at the *end* of a run, so the
    /// glyphs a word starts with are the ones to believe. Unioning the stray in instead
    /// would give a word an extent spanning two printed rows, and the row below would be
    /// swallowed whole.
    /// Do the two APIs describe the same words? They do on a page whose glyph indices line
    /// up with its string once the inserted line breaks are accounted for, and they do not
    /// on one where something else has permuted them.
    ///
    /// The **median** disagreement decides it, not an average and not a worst case: where
    /// PDFKit has merged two printed rows into one line it reports a word's box a couple of
    /// points off, and a handful of those must not condemn a page whose indices are sound.
    private static func agree(_ boxes: [CGRect?], _ ink: [Ink?]) -> Bool {
        var differences: [CGFloat] = []
        for (box, ink) in zip(boxes, ink) {
            guard let box, let ink else { continue }
            guard let xMin = ink.xRange?.lowerBound else { continue }
            differences.append(abs(box.minX - xMin))
        }
        // Too few words to tell is not evidence of agreement.
        guard differences.count >= 4 else { return false }
        return differences.sorted()[differences.count / 2] <= Self.agreementTolerance
    }

    /// A box whose position can be believed. A wrong position is a confidently wrong debit
    /// or credit, so anything null, infinite or hairline-thin is simply not consulted.
    private static func isUsable(_ box: CGRect) -> Bool {
        !box.isNull && box.minX.isFinite && box.maxX.isFinite && box.minY.isFinite
            && box.maxY.isFinite && box.height > 0.5
    }

    private static func overlaps(_ left: ClosedRange<CGFloat>, _ right: ClosedRange<CGFloat>) -> Bool {
        let overlap = min(left.upperBound, right.upperBound) - max(left.lowerBound, right.lowerBound)
        let shorter = min(left.upperBound - left.lowerBound, right.upperBound - right.lowerBound)
        return overlap > shorter / 4
    }

    private static func union(_ left: ClosedRange<CGFloat>, _ right: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        min(left.lowerBound, right.lowerBound)...max(left.upperBound, right.upperBound)
    }

    private static func endOfWord(_ units: [UInt16], from start: Int) -> Int {
        var end = start
        while end < units.count, !isSeparator(units[end]) {
            end += 1
        }
        return end
    }

    private static let newline: UInt16 = 0x000A
    private static let space: UInt16 = 0x0020
    private static let nonBreakingSpace: UInt16 = 0x00A0

    /// A newline is a separator like any other: the text layer's line breaks have no
    /// authority over where a printed row begins or ends.
    private static func isSeparator(_ unit: UInt16) -> Bool {
        unit <= space || unit == nonBreakingSpace
    }
}
