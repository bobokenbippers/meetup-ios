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

    /// One recognized text fragment plus the geometry needed to re-pair it
    /// with neighbours on the same visual row. Vision returns each fragment as
    /// its own observation; on skewed/thermal receipts the right-hand price
    /// column is vertically offset from the item name, so pairing by raw line
    /// index mis-matches prices to items. We re-pair by Y coordinate instead.
    struct OCRObservation {
        let text: String
        let midY: CGFloat   // Vision normalized coords: origin bottom-left, y grows upward
        let minX: CGFloat
        let height: CGFloat
    }

    private static func extractText(from image: UIImage) async -> [String] {
        let processed = preprocessed(image)
        guard let cgImage = processed.cgImage else { return [] }
        // Pass the image orientation so Vision auto-rotates upside-down receipts
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let observations: [OCRObservation] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { o -> OCRObservation? in
                        guard let s = o.topCandidates(1).first?.string else { return nil }
                        let bb = o.boundingBox
                        return OCRObservation(text: s, midY: bb.midY, minX: bb.minX, height: bb.height)
                    }
                continuation.resume(returning: obs)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
        return reassembleRows(observations)
    }

    /// Group OCR fragments into visual rows by Y coordinate, then order each
    /// row left-to-right by X. This re-pairs an offset price column with its
    /// item name. Receipts where Vision already returns a full line as one
    /// observation are unaffected (each row stays a single fragment).
    static func reassembleRows(_ observations: [OCRObservation]) -> [String] {
        guard !observations.isEmpty else { return [] }
        // Top-to-bottom: larger midY is higher on the page.
        let sorted = observations.sorted { $0.midY > $1.midY }
        let heights = sorted.map(\.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.5, 0.005)

        var rows: [[OCRObservation]] = []
        for obs in sorted {
            if let anchor = rows.last?.first, abs(anchor.midY - obs.midY) <= tolerance {
                rows[rows.count - 1].append(obs)
            } else {
                rows.append([obs])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }
                .map(\.text)
                .joined(separator: "  ")
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
        var hasSeenTotal = false

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
            if lower.contains("tip suggestion") || lower.contains("suggested tip") {
                continue
            }
            if line.range(of: #"^\s*(total\s+)?\d{1,2}%\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }

            let matches = priceRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let match = matches.last else {
                continue
            }
            let priceStr = Range(match.range(at: 1), in: line).map { String(line[$0]) }
                        ?? Range(match.range(at: 2), in: line).map { String(line[$0]) }
            guard let priceStr, let price = Double(priceStr), price >= 0.01 else { continue }
            let selectedPriceHasDollarSign = match.range(at: 1).location != NSNotFound

            let isSubtotalLine = subtotalKeywords.contains(where: { lower.contains($0) })
            let isTaxLine = taxKeywords.contains(where: { lower.contains($0) })
            let isTipLine = tipKeywords.contains(where: { lower.contains($0) })
            let isSurchargeLine = surchargeKeywords.contains(where: { lower.contains($0) })
            let isTotalLine = totalKeywords.contains(where: { lower.contains($0) })
            let isSummaryLine = isSubtotalLine || isTaxLine || isTipLine || isSurchargeLine || isTotalLine
            if isSummaryLine, !selectedPriceHasDollarSign, matches.count == 1, line.contains("%") {
                continue
            }

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

            if isSubtotalLine {
                subtotal = price
            } else if isTaxLine {
                tax = price
            } else if isTipLine {
                tip = price
            } else if isSurchargeLine {
                surcharge = price
            } else if isTotalLine {
                if price > total { total = price }
                hasSeenTotal = true
            } else if hasSeenTotal {
                // Receipts often print promos, card metadata, and loyalty copy after total.
                continue
            } else if !summaryKeywords.contains(where: { lower.contains($0) }) {
                // Inline quantity annotation: "(N @ U.UU)" or "N @ U.UU".
                // N = quantity, U = per-unit price. The annotation is NOT the
                // line total: the real total is either a separate price column to
                // its right, or (when that column is absent) N * U. Never treat
                // the bare unit price U as the line price.
                let annotationPattern = #"\(?\s*(\d+)\s*@\s*\$?(\d+(?:\.\d{1,2})?)\s*\)?"#
                var annotationQty: Int? = nil
                var annotationUnit: Double? = nil
                var annotationColumnTotal: Double? = nil
                if let annRegex = try? NSRegularExpression(pattern: annotationPattern),
                   let annMatch = annRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let qRange = Range(annMatch.range(at: 1), in: line),
                   let uRange = Range(annMatch.range(at: 2), in: line),
                   let q = Int(String(line[qRange])), q >= 2, q <= 20,
                   let u = Double(String(line[uRange])), u >= 0.01 {
                    annotationQty = q
                    annotationUnit = u
                    // A price remaining to the right of the annotation is the
                    // real line total (e.g. "(2 @21.00) 42.00").
                    if let annFullRange = Range(annMatch.range, in: line) {
                        var remainder = line
                        remainder.removeSubrange(annFullRange)
                        let remMatches = priceRegex.matches(in: remainder, range: NSRange(remainder.startIndex..., in: remainder))
                        if let remLast = remMatches.last {
                            let rStr = Range(remLast.range(at: 1), in: remainder).map { String(remainder[$0]) }
                                    ?? Range(remLast.range(at: 2), in: remainder).map { String(remainder[$0]) }
                            if let rStr, let rVal = Double(rStr), rVal >= 0.01 {
                                annotationColumnTotal = rVal
                            }
                        }
                    }
                }

                // Standalone price line — check if previous line was a summary label
                var name = line
                if annotationQty != nil {
                    name = name.replacingOccurrences(of: annotationPattern, with: "", options: .regularExpression)
                }
                name = name
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

                // Capture quantity prefixes ("2 ", "4x ") BEFORE the OCR noise
                // strippers run — "4x " is 1-5 consonants + space, so the noise
                // stripper would otherwise eat it. A second capture afterwards
                // handles quantities hidden behind noise (e.g. "I 2 Tacos").
                // Skipped entirely when an inline "@" annotation already set qty.
                var quantity = 1
                let quantityPattern = #"^(\d+)\s*[xX]?\s+"#
                func captureQuantity() {
                    if let qRange = name.range(of: quantityPattern, options: .regularExpression),
                       let qInt = Int(name[qRange].filter(\.isNumber)),
                       qInt >= 2, qInt <= 20 {
                        quantity = qInt
                        name = String(name[qRange.upperBound...])
                    }
                }
                if annotationQty == nil { captureQuantity() }
                // Strip leading all-consonant OCR noise tokens (e.g. "nll "),
                // then leading single-letter artifacts (e.g. "I " misread from "1 ")
                name = name.replacingOccurrences(of: #"^([^aeiouAEIOU\s]{1,5}\s+)+"#, with: "", options: .regularExpression)
                name = name.replacingOccurrences(of: #"^[A-Za-z]\s+"#, with: "", options: .regularExpression)
                if annotationQty == nil {
                    if quantity == 1 { captureQuantity() }
                    name = name.replacingOccurrences(of: quantityPattern, with: "", options: .regularExpression)
                }
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

                // Resolve final quantity + line total.
                //  - Annotation with a separate column total: keep it as a single
                //    line at that total (matches prior column-total behavior).
                //  - Annotation without a column total: line total = N * U,
                //    expanded into N units at U each.
                //  - Otherwise: existing quantity-prefix expansion.
                var lineQuantity = quantity
                var linePrice = price
                if let aq = annotationQty, let au = annotationUnit {
                    if let colTotal = annotationColumnTotal {
                        lineQuantity = 1
                        linePrice = colTotal
                    } else {
                        lineQuantity = aq
                        linePrice = (au * Double(aq) * 100).rounded() / 100
                    }
                }

                if !name.isEmpty {
                    let unitPrice = lineQuantity > 1
                        ? (linePrice / Double(lineQuantity) * 100).rounded() / 100
                        : linePrice
                    for _ in 0..<lineQuantity {
                        items.append((name: name, price: unitPrice))
                    }
                }
            }
        }

        if subtotal == 0 { subtotal = items.reduce(0) { $0 + $1.price } }
        if total == 0 { total = subtotal + tax + tip + surcharge }

        return ParsedReceipt(items: items, subtotal: subtotal, tax: tax, tip: tip, surcharge: surcharge, total: total)
    }
}
