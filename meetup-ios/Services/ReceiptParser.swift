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
        guard let doc = PDFDocument(url: pdfURL),
              let page = doc.page(at: 0) else {
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
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
    }

    static func parseText(_ lines: [String]) -> ParsedReceipt {
        let pricePattern = #"(\d+\.\d{2})"#
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
            + ["change", "cash", "credit", "visa", "mastercard", "amex", "thank you", "receipt"]

        for line in lines {
            let lower = line.lowercased()
            guard let match = priceRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line),
                  let price = Double(line[range]) else { continue }

            if subtotalKeywords.contains(where: { lower.contains($0) }) {
                subtotal = price
            } else if taxKeywords.contains(where: { lower.contains($0) }) {
                tax = price
            } else if tipKeywords.contains(where: { lower.contains($0) }) {
                tip = price
            } else if totalKeywords.contains(where: { lower.contains($0) }) {
                if price > total { total = price }
            } else if !summaryKeywords.contains(where: { lower.contains($0) }) {
                let name = line
                    .replacingOccurrences(of: pricePattern, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
                    .trimmingCharacters(in: .whitespaces)
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
