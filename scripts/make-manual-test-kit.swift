#!/usr/bin/env swift
//
// Generates the seven documents the manual import gate needs (T129,
// `specs/016-statement-import-vertical/quickstart.md` §5), so that gate never needs a real
// statement to run — and so nobody is tempted to reach for one.
//
// Every document is synthesised here from invented figures. Nothing is committed: the PDFs
// are build output, and `fixtures/` stays free of binary blobs (Constitution V, FR-043).
//
//     swift scripts/make-manual-test-kit.swift ~/kaname-test-kit
//
// Then drag the folder onto a booted simulator and save it into "On My iPhone".
//
//   1-supported-statement.pdf  reads as ICICI_AMAZONPAY_CARD, 3 transactions
//   2-image-only.pdf           words are pixels, no text layer  -> "This looks like a scan"
//   3-password-kaname.pdf      user password `kaname`
//   4-corrupt.pdf              a valid PDF with its second half cut off
//   5-not-a-pdf.pdf            plain text wearing a PDF's name
//   6-utility-bill.pdf         text-bearing, claims no issuer   -> "doesn't read this yet"
//   7-long-for-cancel.pdf      31 rows, so Cancel has something to interrupt

import CoreGraphics
import CoreText
import Foundation

let pageSize = CGSize(width: 595, height: 842)
let leftMargin: CGFloat = 40
let topMargin: CGFloat = 60
// Comfortably more than the font size: rows this far apart are unambiguous to the
// geometry-first extractor, so a failure in the app is the app's and not the document's.
let lineSpacing: CGFloat = 22
let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)

func draw(_ lines: [String], into ctx: CGContext) {
    for (index, text) in lines.enumerated() {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
        )
        ctx.textPosition = CGPoint(
            x: leftMargin,
            y: pageSize.height - topMargin - CGFloat(index) * lineSpacing
        )
        CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
    }
}

func writeTextPDF(_ lines: [String], to url: URL, userPassword: String? = nil) {
    var box = CGRect(origin: .zero, size: pageSize)
    var options: [CFString: Any] = [:]
    if let userPassword {
        options[kCGPDFContextUserPassword] = userPassword
        options[kCGPDFContextOwnerPassword] = userPassword + "-owner"
    }
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, options as CFDictionary) else {
        fatalError("could not open \(url.lastPathComponent) for writing")
    }
    ctx.beginPDFPage(nil)
    draw(lines, into: ctx)
    ctx.endPDFPage()
    ctx.closePDF()
}

/// A page whose words exist only as pixels, which is what a scanned statement is.
func writeImageOnlyPDF(_ lines: [String], to url: URL) {
    let scale: CGFloat = 2
    let pixels = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
    guard
        let bitmap = CGContext(
            data: nil,
            width: Int(pixels.width),
            height: Int(pixels.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { fatalError("could not create the bitmap") }
    bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    bitmap.fill(CGRect(origin: .zero, size: pixels))
    bitmap.scaleBy(x: scale, y: scale)
    draw(lines, into: bitmap)
    guard let image = bitmap.makeImage() else { fatalError("could not rasterise the page") }

    var box = CGRect(origin: .zero, size: pageSize)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
        fatalError("could not open \(url.lastPathComponent) for writing")
    }
    ctx.beginPDFPage(nil)
    ctx.draw(image, in: box)
    ctx.endPDFPage()
    ctx.closePDF()
}

// The card lines are the ones `ios/Tests/ExtractionFidelityTests.swift` is fixture-locked
// against, plus one more row of the same shape. Invented, and deliberately not a real card
// number: `4315XXXXXXXX1002` is how the statement itself masks one.
let supported = [
    "ICICI Bank Statement",
    "Statement Date May 28, 2026",
    "4315XXXXXXXX1002",
    "29/04/2026 4262 BBPS Payment received 0 13,628.36 CR",
    "26/05/2026 1814 Fee on gaming transaction 0 10.20",
    "26/05/2026 2201 Coffee and a sandwich 0 480.00",
]

// A real document that is emphatically not a statement, so "Kaname doesn't read this
// statement yet" is reached by a document no reader claims rather than by a broken one.
let utilityBill = [
    "MUNICIPAL WATER SUPPLY BOARD",
    "Consumer Bill - Quarter ending May 2026",
    "Consumer No 88-4412-09",
    "Meter reading previous 004182  present 004257",
    "Units consumed 75",
    "Amount payable Rs. 1,125.00 due by 15/06/2026",
]

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

writeTextPDF(supported, to: out.appendingPathComponent("1-supported-statement.pdf"))
writeImageOnlyPDF(supported, to: out.appendingPathComponent("2-image-only.pdf"))
writeTextPDF(supported, to: out.appendingPathComponent("3-password-kaname.pdf"), userPassword: "kaname")
writeTextPDF(utilityBill, to: out.appendingPathComponent("6-utility-bill.pdf"))

// Corrupt: the header still says PDF and nothing after it can be believed, which is the
// case that separates "not a PDF" from "a PDF I could not parse".
let whole = out.appendingPathComponent(".whole.pdf")
writeTextPDF(supported, to: whole)
let bytes = try Data(contentsOf: whole)
try bytes.prefix(bytes.count / 2).write(to: out.appendingPathComponent("4-corrupt.pdf"))
try FileManager.default.removeItem(at: whole)

try Data("This is a plain text file wearing a PDF's name.\n".utf8)
    .write(to: out.appendingPathComponent("5-not-a-pdf.pdf"))

var long = Array(supported.prefix(3))
for day in 1...28 {
    long.append(String(format: "%02d/05/2026", day) + " \(3000 + day) Purchase number \(day) 0 \(day * 37).50")
}
writeTextPDF(long, to: out.appendingPathComponent("7-long-for-cancel.pdf"))

print("wrote 7 documents to \(out.path)")
