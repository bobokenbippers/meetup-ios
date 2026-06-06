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
    var surcharge: Double
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
            return ParsedReceipt(items: [], subtotal: 0, tax: 0, tip: 0, surcharge: 0, total: 0)
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
            return ParsedReceipt(items: [], subtotal: 0, tax: 0, tip: 0, surcharge: 0, total: 0)
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

    private static func preprocessed(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let context = CIContext()
        // Grayscale + contrast boost — improves OCR on low-contrast receipt paper
        let gray = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.2,
            kCIInputBrightnessKey: 0.05
        ])
        guard let cgOut = context.createCGImage(gray, from: gray.extent) else { return image }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func extractText(from image: UIImage) async -> [String] {
        let processed = preprocessed(image)
        guard let cgImage = processed.cgImage else { return [] }
        // Pass the image orientation so Vision auto-rotates upside-down receipts
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
        }
    }

    static func parseText(_ lines: [String]) -> ParsedReceipt {
        // Also handle European-style numbers (comma as decimal separator)
        let normalizedLines = lines.map { line -> String in
            // Replace patterns like "35,84" (digit-comma-2digits) with "35.84"
            let commaDecimal = try! NSRegularExpression(pattern: #"\b(\d+),(\d{2})\b"#)
            let range = NSRange(line.startIndex..., in: line)
            return commaDecimal.stringByReplacingMatches(in: line, range: range, withTemplate: "$1.$2")
        }

        let pricePattern = #"\$(\d+(?:\.\d{1,2})?)|\b(\d+\.\d{1,2})\b"#
        let priceRegex = try! NSRegularExpression(pattern: pricePattern)

        var items: [(name: String, price: Double)] = []
        var subtotal: Double = 0
        var tax: Double = 0
        var tip: Double = 0
        var surcharge: Double = 0
        var total: Double = 0

        let subtotalKeywords = ["subtotal", "sub total", "sub-total"]
        let taxKeywords = ["tax", "hst", "gst", "vat", "sales tax"]
        let tipKeywords = ["tip", "gratuity", "service charge"]
        let surchargeKeywords = ["surcharge", "credit card", "card fee", "processing fee", "cc fee", "convenience fee"]
        let totalKeywords = ["total", "amount due", "balance due", "grand total"]
        let summaryKeywords = subtotalKeywords + taxKeywords + tipKeywords + surchargeKeywords + totalKeywords
            + ["change", "cash", "credit", "visa", "mastercard", "amex", "thank you", "receipt",
               "no refund", "transactions are final", "qr", "tel", "fax", "no. of guest",
               "server", "tab#", "dine in", "table", "check", "guest", "amount"]

        for (idx, line) in normalizedLines.enumerated() {
            let lower = line.lowercased()
            guard let match = priceRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }
            let priceStr = Range(match.range(at: 1), in: line).map { String(line[$0]) }
                        ?? Range(match.range(at: 2), in: line).map { String(line[$0]) }
            guard let priceStr, let price = Double(priceStr), price >= 0.01 else { continue }

            // Helper: resolve what the previous label line was when price is on its own line
            func prevLineCategory() -> String? {
                guard idx > 0 else { return nil }
                let prev = normalizedLines[idx - 1].lowercased()
                let prevHasPrice = priceRegex.firstMatch(
                    in: normalizedLines[idx - 1],
                    range: NSRange(normalizedLines[idx - 1].startIndex..., in: normalizedLines[idx - 1])
                ) != nil
                guard !prevHasPrice else { return nil }
                if subtotalKeywords.contains(where: { prev.contains($0) })  { return "subtotal" }
                if taxKeywords.contains(where: { prev.contains($0) })       { return "tax" }
                if tipKeywords.contains(where: { prev.contains($0) })       { return "tip" }
                if surchargeKeywords.contains(where: { prev.contains($0) }) { return "surcharge" }
                if totalKeywords.contains(where: { prev.contains($0) })     { return "total" }
                return nil
            }

            if subtotalKeywords.contains(where: { lower.contains($0) }) {
                subtotal = price
            } else if taxKeywords.contains(where: { lower.contains($0) }) {
                tax = price
            } else if tipKeywords.contains(where: { lower.contains($0) }) {
                tip = price
            } else if surchargeKeywords.contains(where: { lower.contains($0) }) {
                surcharge = price
            } else if totalKeywords.contains(where: { lower.contains($0) }) {
                if price > total { total = price }
            } else if !summaryKeywords.contains(where: { lower.contains($0) }) {
                // Standalone price line — check if previous line was a summary label
                var name = line
                    .replacingOccurrences(of: pricePattern, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
                    .trimmingCharacters(in: .whitespaces)

                if name.isEmpty {
                    // Price-on-own-line: check if prev was a summary label first
                    switch prevLineCategory() {
                    case "subtotal":  subtotal = price;                         continue
                    case "tax":       tax = price;                               continue
                    case "tip":       tip = price;                               continue
                    case "surcharge": surcharge = price;                         continue
                    case "total":     if price > total { total = price };        continue
                    default: break
                    }
                }

                // Strip leading all-consonant OCR noise tokens (e.g. "nll "),
                // then leading single-letter artifacts (e.g. "I " misread from "1 "),
                // then leading quantity digits (e.g. "1 ", "2 ")
                name = name.replacingOccurrences(of: #"^([^aeiouAEIOU\s]{1,5}\s+)+"#, with: "", options: .regularExpression)
                name = name.replacingOccurrences(of: #"^[A-Za-z]\s+"#, with: "", options: .regularExpression)
                name = name.replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression)
                name = name.trimmingCharacters(in: .whitespaces)

                // Skip modifier lines like "**w.Salad"
                if name.hasPrefix("*") { continue }

                // Require at least 2 letters — reject pure punctuation/noise like "("
                let letterCount = name.filter(\.isLetter).count
                let effectivelyEmpty = letterCount < 2

                if effectivelyEmpty {
                    // Treat as standalone price — check if prev line was a summary label
                    switch prevLineCategory() {
                    case "subtotal":  subtotal = price;                         continue
                    case "tax":       tax = price;                               continue
                    case "tip":       tip = price;                               continue
                    case "surcharge": surcharge = price;                         continue
                    case "total":     if price > total { total = price };        continue
                    default: continue  // discard noise item
                    }
                }

                // If name is still empty after cleaning, use previous non-summary, non-price line
                if name.isEmpty, idx > 0 {
                    let prev = normalizedLines[idx - 1]
                    let prevLower = prev.lowercased()
                    let prevHasPrice = priceRegex.firstMatch(in: prev, range: NSRange(prev.startIndex..., in: prev)) != nil
                    let prevIsSummary = summaryKeywords.contains(where: { prevLower.contains($0) })
                    if !prevHasPrice && !prevIsSummary && !prev.hasPrefix("*") {
                        var prevName = prev.trimmingCharacters(in: .whitespaces)
                        prevName = prevName
                            .replacingOccurrences(of: #"^([^aeiouAEIOU\s]{1,5}\s+)+"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"^[A-Za-z]\s+"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespaces)
                        name = prevName
                    }
                }

                if !name.isEmpty {
                    items.append((name: name, price: price))
                }
            }
        }

        if subtotal == 0 { subtotal = items.reduce(0) { $0 + $1.price } }
        if total == 0 { total = subtotal + tax + tip + surcharge }

        return ParsedReceipt(items: items, subtotal: subtotal, tax: tax, tip: tip, surcharge: surcharge, total: total)
    }
}
