import Foundation
import UIKit
import Supabase

/// Vision-LLM receipt parsing.
///
/// Sends a scanned receipt image to the `parse-receipt` Supabase Edge Function,
/// which calls Claude (vision) and returns clean, structured line items. This
/// is dramatically more accurate on messy bar/restaurant receipts than the
/// local Apple Vision + regex parser.
///
/// `ReceiptParser` (local, on-device) remains the graceful fallback: callers
/// should invoke `parse(image:)` here and fall back to `ReceiptParser.parse`
/// if it throws (no network, function not deployed, API key missing, etc.).
///
/// Output is mapped into the existing `ParsedReceipt` model so the rest of the
/// app is unchanged: quantities are expanded into individual claimable rows and
/// no-price modifier lines are dropped.
enum ReceiptVisionService {

    enum VisionError: Error {
        case encodingFailed
        case emptyResult
    }

    // MARK: - Wire types (match the edge function's JSON schema)

    struct VisionItem: Decodable {
        let name: String
        let qty: Int
        let unitPrice: Double
        let lineTotal: Double
        let isModifier: Bool
    }

    struct VisionResponse: Decodable {
        let items: [VisionItem]
        let subtotal: Double
        let tax: Double
        let tip: Double
        let total: Double
    }

    private struct VisionRequest: Encodable {
        let image: String
        let mediaType: String
    }

    // MARK: - API

    /// Parse a receipt image via the vision LLM. Throws on any failure so the
    /// caller can fall back to the local parser.
    static func parse(image: UIImage) async throws -> ParsedReceipt {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw VisionError.encodingFailed
        }
        let base64 = jpeg.base64EncodedString()
        let request = VisionRequest(image: base64, mediaType: "image/jpeg")

        // The Supabase Functions client throws `FunctionsError.httpError` for any
        // non-2xx response, so a server-side failure (missing API key, model
        // error, etc.) propagates out of `invoke` and is caught by the caller,
        // which then falls back to the local parser.
        let supabase = SupabaseManager.shared.client
        let response: VisionResponse = try await supabase.functions.invoke(
            "parse-receipt",
            options: .init(body: request),
            decoder: JSONDecoder()
        )

        guard !response.items.isEmpty || response.subtotal > 0 || response.total > 0 else {
            throw VisionError.emptyResult
        }
        return map(response)
    }

    /// Decode a raw edge-function JSON payload into a `ParsedReceipt`. Exposed
    /// for tests that exercise the decode + mapping layer without networking.
    static func parse(jsonData: Data) throws -> ParsedReceipt {
        let response = try JSONDecoder().decode(VisionResponse.self, from: jsonData)
        return map(response)
    }

    // MARK: - Mapping

    /// Map the structured vision response into the app's `ParsedReceipt`.
    ///
    /// - Modifier lines (`isModifier == true`) are dropped — they belong to the
    ///   item above and carry no price of their own.
    /// - Each item's quantity is expanded into individual rows so each unit can
    ///   be claimed separately, matching the local parser's behaviour. The
    ///   per-row price is the unit price.
    /// - The printed subtotal/tax/total are trusted as-is (no reconciliation
    ///   against any external menu).
    static func map(_ response: VisionResponse) -> ParsedReceipt {
        var items: [(name: String, price: Double)] = []

        for item in response.items {
            // Drop modifiers and anything without a real name.
            let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isModifier || trimmedName.isEmpty { continue }

            let qty = max(1, item.qty)

            // Prefer the printed unit price. If it's missing but a line total is
            // present, derive the unit price from the line total / qty.
            var unitPrice = item.unitPrice
            if unitPrice <= 0 && item.lineTotal > 0 {
                unitPrice = (item.lineTotal / Double(qty) * 100).rounded() / 100
            }

            // Skip zero-priced billable lines — nothing to split.
            guard unitPrice > 0 else { continue }

            for _ in 0..<qty {
                items.append((name: trimmedName, price: unitPrice))
            }
        }

        // Trust the receipt's printed totals. Only synthesize when absent.
        let subtotal = response.subtotal > 0
            ? response.subtotal
            : items.reduce(0) { $0 + $1.price }
        let total = response.total > 0
            ? response.total
            : subtotal + response.tax + response.tip

        return ParsedReceipt(
            items: items,
            subtotal: subtotal,
            tax: response.tax,
            tip: response.tip,
            surcharge: 0,
            total: total
        )
    }
}
