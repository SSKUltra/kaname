import Foundation
import UIKit

/// How a column anchors its cells: `left` puts `x` at the cell's left edge, `right` at its
/// right edge — which is how amount columns are printed.
enum ColumnAlignment: String, Decodable, Sendable {
    case left
    case right
}

/// A line printed somewhere other than the table or the header block: an address block
/// beside a summary box, a narration that wrapped out of its column, a page header that
/// repeats down the sheet. Placed in PDF space, so a vector can put it exactly where the
/// hazard it models needs it.
struct PlacedLine: Decodable, Sendable {
    let text: String
    let left: Double
    let top: Double

    enum CodingKeys: String, CodingKey {
        case text
        case left = "x"
        case top = "y"
    }
}

/// One column of a fixture's table.
struct GeometryColumn: Decodable, Sendable {
    /// The cell key this column draws — `date`, `description`, `amount`, `direction` for a
    /// card; the ledger roles for a bank account.
    let role: String
    /// The column's anchor in PDF space, read from the fixture's `x`.
    let anchorX: Double
    let align: ColumnAlignment

    enum CodingKeys: String, CodingKey {
        case role
        case anchorX = "x"
        case align
    }
}

/// A **layout signature** and the cells drawn from it — the fixture format defined by
/// `specs/017-column-major-pdf/contracts/geometry-fixture.md`.
///
/// A signature carries no values, so a document rendered from one is synthetic by
/// construction: nothing is stripped, so nothing can survive stripping. That is why these
/// fixtures may live in an open repository at all (ADR-0004, amendment 2026-08-13).
struct GeometryFixture: Decodable, Sendable {
    struct Signature: Decodable, Sendable {
        let pageSize: [Double]
        let fontSize: Double
        /// Baseline-to-baseline distance between printed rows, in points.
        let rowPitch: Double
        /// The top of the first printed row, in PDF space (origin bottom-left).
        let firstRowY: Double
        let dateFormat: String
        let columns: [GeometryColumn]
        /// How many rows each page prints, when the vector spans more than one. A leading
        /// `0` puts the whole first page's worth of identity above the table, so the first
        /// transaction row lands on page **two** — which is what proves the row-1 bootstrap
        /// still knows where the figures were printed off page one.
        let rowsPerPage: [Int]?

        var width: Double { pageSize.first ?? 595 }
        var height: Double { pageSize.count > 1 ? pageSize[1] : 842 }
    }

    struct Transaction: Decodable, Sendable, Equatable {
        let date: String
        let amount: String
        let direction: String
        let descriptionRaw: String
    }

    struct Expected: Decodable, Sendable {
        let issuerId: String
        let transactions: [Transaction]
        /// The most transactions the **pre-slice** extraction may recover from this
        /// document. Assertion A4 requires it to be strictly less than
        /// `transactions.count`, which is what stops a vacuous fixture being mistaken for
        /// proof of the fix.
        let legacyMaxTransactions: Int
        /// The running balance a bank-account vector prints last, as printed. The balance
        /// chain has to arrive back at it.
        let closingBalance: String?
        /// Where a bank-account vector's **first** row must get its direction from. A
        /// vector that prints no opening balance says `Row1XPosition` here, which holds
        /// only if the amount's printed column survived reshaping.
        let directionSource: String?
    }

    let issuerId: String
    let kind: String
    let signature: Signature
    let headerLines: [String]
    let footerLines: [String]
    /// Printed on the first page at their own coordinates, after the table — the escape
    /// hatch for everything a bank prints that is not a header, a footer or a row.
    let extraLines: [PlacedLine]?
    /// One printed row per element, keyed by column role. A role a row does not print is
    /// simply absent — a blank cell, not an empty string in the wrong slot.
    let rows: [[String: String]]
    let expected: Expected
}

enum GeometryFixtureError: Error, CustomStringConvertible {
    case layoutDoesNotFit(String)
    case missingFixture(String)

    var description: String {
        switch self {
        case .layoutDoesNotFit(let detail): "the fixture's signature does not fit its page: \(detail)"
        case .missingFixture(let name): "no fixture named \(name) is bundled"
        }
    }
}

/// Draws a fixture into a real PDF, **column-major**.
///
/// Column-major is the whole point (contract R1): drawing every cell of column 1 top to
/// bottom, then every cell of column 2, is what makes the platform's text layer emit the
/// page column-major — which is the shape that made real statements report no spending.
/// A row-major fixture would pass both before and after the fix and prove nothing.
enum GeometryFixtureRenderer {
    /// Where the fixture's PDF-space `y` (origin bottom-left) lands in UIKit's drawing
    /// space (origin top-left), which is what `NSString.draw(at:)` takes.
    private static func topY(_ pdfY: Double, in signature: GeometryFixture.Signature) -> Double {
        signature.height - pdfY
    }

    static func render(_ fixture: GeometryFixture, to url: URL) throws {
        let signature = fixture.signature
        let pitch = signature.rowPitch
        let firstRowTop = topY(signature.firstRowY, in: signature)
        let headerTop = firstRowTop - Double(fixture.headerLines.count) * pitch
        let pages = Self.pages(of: fixture)
        let longest = pages.map(\.count).max() ?? 0
        let footerTop = firstRowTop + Double(longest + 1) * pitch

        guard headerTop >= 0 else {
            throw GeometryFixtureError.layoutDoesNotFit("\(fixture.headerLines.count) header lines above first_row_y")
        }
        guard footerTop + Double(fixture.footerLines.count) * pitch <= signature.height else {
            throw GeometryFixtureError.layoutDoesNotFit("\(fixture.footerLines.count) footer lines below the rows")
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: CGFloat(signature.fontSize), weight: .regular)
        ]
        let bounds = CGRect(x: 0, y: 0, width: signature.width, height: signature.height)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let left = signature.columns.first?.anchorX ?? 0

        try renderer.writePDF(to: url) { context in
            for (number, rows) in pages.enumerated() {
                context.beginPage()

                // R3: header and footer are ordinary single-column lines. They carry the
                // claim markers, and must stay recognisable through the reshaping.
                if number == 0 {
                    for (index, line) in fixture.headerLines.enumerated() {
                        draw(line, atX: left, topY: headerTop + Double(index) * pitch, attributes)
                    }
                    for line in fixture.extraLines ?? [] {
                        draw(line.text, atX: line.left, topY: topY(line.top, in: signature), attributes)
                    }
                }

                drawTable(rows, of: signature, from: firstRowTop, attributes)

                if number == pages.count - 1 {
                    for (index, line) in fixture.footerLines.enumerated() {
                        draw(line, atX: left, topY: footerTop + Double(index) * pitch, attributes)
                    }
                }
            }
        }
    }

    /// R1 + R2: column-major — every cell of column 1 top to bottom, then column 2, and so
    /// on — each cell at its column's x and its row's y.
    private static func drawTable(
        _ rows: [[String: String]],
        of signature: GeometryFixture.Signature,
        from firstRowTop: Double,
        _ attributes: [NSAttributedString.Key: Any]
    ) {
        for column in signature.columns {
            for (index, row) in rows.enumerated() {
                guard let cell = row[column.role], !cell.isEmpty else { continue }
                let cellX = originX(of: cell, in: column, attributes)
                draw(cell, atX: cellX, topY: firstRowTop + Double(index) * signature.rowPitch, attributes)
            }
        }
    }

    /// The fixture's rows, split across the pages its signature asks for.
    private static func pages(of fixture: GeometryFixture) -> [[[String: String]]] {
        guard let counts = fixture.signature.rowsPerPage, !counts.isEmpty else { return [fixture.rows] }
        var pages: [[[String: String]]] = []
        var cursor = 0
        for count in counts {
            let end = min(cursor + max(0, count), fixture.rows.count)
            pages.append(Array(fixture.rows[cursor..<end]))
            cursor = end
        }
        if cursor < fixture.rows.count { pages.append(Array(fixture.rows[cursor...])) }
        return pages
    }

    private static func originX(
        of cell: String,
        in column: GeometryColumn,
        _ attributes: [NSAttributedString.Key: Any]
    ) -> Double {
        switch column.align {
        case .left: column.anchorX
        case .right: column.anchorX - Double((cell as NSString).size(withAttributes: attributes).width)
        }
    }

    private static func draw(
        _ text: String,
        atX originX: Double,
        topY: Double,
        _ attributes: [NSAttributedString.Key: Any]
    ) {
        (text as NSString).draw(at: CGPoint(x: originX, y: topY), withAttributes: attributes)
    }
}

/// Every vector in `fixtures/geometry/`, copied into the test bundle by `ios/Project.swift`.
enum GeometryFixtureLoader {
    private final class BundleToken {}

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static var urls: [URL] {
        let bundle = Bundle(for: BundleToken.self)
        let found = bundle.urls(forResourcesWithExtension: "json", subdirectory: "geometry") ?? []
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The fixture file names, which are what the suite is parameterised over so a failure
    /// names the vector that failed.
    static let names: [String] = urls.map(\.lastPathComponent)

    static func load(_ name: String) throws -> GeometryFixture {
        guard let url = urls.first(where: { $0.lastPathComponent == name }) else {
            throw GeometryFixtureError.missingFixture(name)
        }
        return try decoder.decode(GeometryFixture.self, from: Data(contentsOf: url))
    }
}
