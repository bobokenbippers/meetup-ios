import Vision
import UIKit
import PDFKit

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
        // Camera images carry EXIF rotation in imageOrientation — cgImage is the raw
        // un-rotated sensor data. Redraw into a fresh context so Vision sees upright pixels.
        let normalized = normalizeOrientation(image)
        guard let cgImage = normalized.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
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
        let totalKeywords = ["total", "amount due", "balance due", "grand total"]
        let summaryKeywords = subtotalKeywords + taxKeywords + tipKeywords + totalKeywords
            + ["change", "cash", "credit", "visa", "mastercard", "amex", "thank you", "receipt",
               "surcharge", "fee", "discount", "happy hour", "join us", "book your",
               "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
               "www.", "email", "phone", "for more", "fill out", "online form", "private event",
               "mini martini", "special offer", "oyster monday"]

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
                // Strip the line-item price, per-unit annotations (e.g. "3$"), and OCR artifacts.
                var name = line
                    .replacingOccurrences(of: pricePattern, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\b\d+\$"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\bsingle\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                // Remove OCR garbage: runs of characters that aren't letters, digits, spaces, or basic punctuation
                name = name.replacingOccurrences(of: #"[^a-zA-Z0-9\s',\.\-&]+"#, with: " ", options: .regularExpression)
                // Strip trailing isolated 1-2 char noise tokens from photo background texture (e.g. "Ue.", "Sy ae")
                // Capped at 2 chars to avoid stripping real short words like "Bun", "Bao", "Oil"
                name = name.replacingOccurrences(of: #"(\s+[A-Za-z]{1,2}\.?){1,4}\s*$"#, with: "", options: .regularExpression)
                // Strip trailing digit + short-char noise (e.g. "2 Oe i" from OCR misreading background)
                name = name.replacingOccurrences(of: #"\s+\d+(\s+[A-Za-z]{1,2})+\s*$"#, with: "", options: .regularExpression)
                // Collapse multiple spaces
                name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                // Skip if the name is mostly non-letter content (OCR noise line)
                let letterCount = name.filter(\.isLetter).count
                if !name.isEmpty && letterCount >= 3 {
                    items.append((name: name, price: price))
                }
            }
        }

        if subtotal == 0 { subtotal = items.reduce(0) { $0 + $1.price } }
        if total == 0 { total = subtotal + tax + tip }

        return ParsedReceipt(items: items, subtotal: subtotal, tax: tax, tip: tip, total: total)
    }
}
