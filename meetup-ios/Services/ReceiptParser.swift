import Vision
import UIKit
import PDFKit
import ImageIO

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

struct ParsedReceipt {
    var items: [(name: String, price: Double)]
    var subtotal: Double
    var tax: Double
    var tip: Double
    var total: Double
}

struct ReceiptParser {

    static func parse(image: UIImage) async -> ParsedReceipt {
        let lines = await extractText(from: image)
        return parseText(lines)
    }

    static func parse(pdfURL: URL) async -> ParsedReceipt {
        // Prefer embedded text extraction — fast and lossless.
        // Fall back to Vision OCR only if the PDF has no selectable text (scanned receipt).
        let accessed = pdfURL.startAccessingSecurityScopedResource()
        defer { if accessed { pdfURL.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: pdfURL) else {
            return ParsedReceipt(items: [], subtotal: 0, tax: 0, tip: 0, total: 0)
        }

        // Try embedded text across all pages
        let embeddedText = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")
        let embeddedLines = embeddedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if !embeddedLines.isEmpty {
            return parseText(embeddedLines)
        }

        // Scanned PDF — rasterize page 0 and OCR it
        guard let page = doc.page(at: 0) else {
            return ParsedReceipt(items: [], subtotal: 0, tax: 0, tip: 0, total: 0)
        }
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let img = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0, y: pageRect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return await parse(image: img)
    }

    // MARK: - Private

    private static func extractText(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        // Pass the image orientation so Vision auto-rotates upside-down receipts
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
        }
    }

    static func parseText(_ lines: [String]) -> ParsedReceipt {
        let pricePattern = #"\$(\d+(?:\.\d{1,2})?)|\b(\d+\.\d{1,2})\b"#
        let priceRegex = try! NSRegularExpression(pattern: pricePattern)

        var items: [(name: String, price: Double)] = []
        var subtotal: Double = 0
        var tax: Double = 0
        var tip: Double = 0
        var total: Double = 0

        let subtotalKeywords = ["subtotal", "sub total", "sub-total"]
        let taxKeywords = ["tax", "hst", "gst", "vat", "sales tax"]
        let tipKeywords = ["tip", "gratuity", "service charge"]
        let totalKeywords = ["total", "amount due", "balance due", "grand total", "amount"]
        let summaryKeywords = subtotalKeywords + taxKeywords + tipKeywords + totalKeywords
            + ["change", "cash", "credit", "visa", "mastercard", "amex", "thank you", "receipt",
               "no refund", "transactions are final", "qr", "tel", "fax", "no. of guest",
               "server", "tab#", "dine in", "table", "check", "guest"]

        for line in lines {
            let lower = line.lowercased()
            guard let match = priceRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            let priceStr = Range(match.range(at: 1), in: line).map { String(line[$0]) }
                        ?? Range(match.range(at: 2), in: line).map { String(line[$0]) }
            guard let priceStr, let price = Double(priceStr), price >= 0.01 else { continue }

            if subtotalKeywords.contains(where: { lower.contains($0) }) {
                subtotal = price
            } else if taxKeywords.contains(where: { lower.contains($0) }) {
                tax = price
            } else if tipKeywords.contains(where: { lower.contains($0) }) {
                tip = price
            } else if totalKeywords.contains(where: { lower.contains($0) }) {
                if price > total { total = price }
            } else if !summaryKeywords.contains(where: { lower.contains($0) }) {
                var name = line
                    .replacingOccurrences(of: pricePattern, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
                    .trimmingCharacters(in: .whitespaces)
                // Strip leading quantity like "1 " or "2 "
                if let qtyRange = name.range(of: #"^\d+\s+"#, options: .regularExpression) {
                    name = String(name[qtyRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                // Skip modifier lines like "**w.Salad"
                if name.hasPrefix("*") { continue }
                if !name.isEmpty {
                    items.append((name: name, price: price))
                }
            }
        }

        if subtotal == 0 { subtotal = items.reduce(0) { $0 + $1.price } }
        if total == 0 { total = subtotal + tax + tip }

        return ParsedReceipt(items: items, subtotal: subtotal, tax: tax, tip: tip, total: total)
    }
}
