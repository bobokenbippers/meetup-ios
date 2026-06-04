import Foundation
import Supabase

final class BillService {
    static let shared = BillService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Bill CRUD

    func fetchBill(meetupId: UUID) async throws -> Bill? {
        let rows: [Bill] = try await supabase
            .from("bills")
            .select()
            .eq("meetup_id", value: meetupId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func createBill(meetupId: UUID, receipt: ParsedReceipt) async throws -> (Bill, [BillItem]) {
        guard let userId = supabase.auth.currentUser?.id else { throw BillError.notSignedIn }

        struct BillInsert: Encodable {
            let meetupId: UUID
            let createdBy: UUID
            let subtotal: Double
            let tax: Double
            let tip: Double
            let total: Double
            enum CodingKeys: String, CodingKey {
                case subtotal, tax, tip, total
                case meetupId  = "meetup_id"
                case createdBy = "created_by"
            }
        }

        let billInsert = BillInsert(
            meetupId: meetupId,
            createdBy: userId,
            subtotal: receipt.subtotal,
            tax: receipt.tax,
            tip: receipt.tip,
            total: receipt.total
        )
        let bills: [Bill] = try await supabase
            .from("bills")
            .insert(billInsert)
            .select()
            .execute()
            .value
        guard let bill = bills.first else { throw BillError.createFailed }

        let items = try await insertItems(billId: bill.id, parsedItems: receipt.items)
        return (bill, items)
    }

    func fetchItems(billId: UUID) async throws -> [BillItem] {
        try await supabase
            .from("bill_items")
            .select()
            .eq("bill_id", value: billId)
            .order("position")
            .execute()
            .value
    }

    func updateItem(_ item: BillItem) async throws {
        struct ItemUpdate: Encodable {
            let name: String
            let price: Double
        }
        try await supabase
            .from("bill_items")
            .update(ItemUpdate(name: item.name, price: item.price))
            .eq("id", value: item.id)
            .execute()
    }

    // MARK: - Claims

    func fetchClaims(billId: UUID) async throws -> [BillItemClaim] {
        let items = try await fetchItems(billId: billId)
        guard !items.isEmpty else { return [] }
        return try await supabase
            .from("bill_item_claims")
            .select()
            .in("bill_item_id", values: items.map { $0.id.uuidString })
            .execute()
            .value
    }

    func claimItem(billItemId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { throw BillError.notSignedIn }
        struct ClaimInsert: Encodable {
            let billItemId: UUID
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case billItemId = "bill_item_id"
                case userId     = "user_id"
            }
        }
        try await supabase
            .from("bill_item_claims")
            .insert(ClaimInsert(billItemId: billItemId, userId: userId))
            .execute()
    }

    func unclaimItem(billItemId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { throw BillError.notSignedIn }
        try await supabase
            .from("bill_item_claims")
            .delete()
            .eq("bill_item_id", value: billItemId)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Totals

    struct PersonTotal {
        let userId: UUID
        var displayName: String
        var subtotal: Double
        var taxShare: Double
        var tipShare: Double
        var total: Double
    }

    static func computeTotals(
        bill: Bill,
        items: [BillItem],
        claims: [BillItemClaim],
        participants: [MeetupParticipant]
    ) -> [PersonTotal] {
        var subtotals: [UUID: Double] = [:]
        for item in items {
            let claimants = claims.filter { $0.billItemId == item.id }.map { $0.userId }
            guard !claimants.isEmpty else { continue }
            let share = item.price / Double(claimants.count)
            for uid in claimants {
                subtotals[uid, default: 0] += share
            }
        }
        return participants
            .map { p in
                let sub = subtotals[p.userId] ?? 0
                let taxShare = bill.subtotal > 0 ? (sub / bill.subtotal) * bill.tax : 0
                let tipShare = bill.subtotal > 0 ? (sub / bill.subtotal) * bill.tip : 0
                return PersonTotal(
                    userId: p.userId,
                    displayName: p.displayName ?? "Unknown",
                    subtotal: sub,
                    taxShare: taxShare,
                    tipShare: tipShare,
                    total: sub + taxShare + tipShare
                )
            }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Private

    private func insertItems(billId: UUID, parsedItems: [(name: String, price: Double)]) async throws -> [BillItem] {
        struct ItemInsert: Encodable {
            let billId: UUID
            let name: String
            let price: Double
            let position: Int
            enum CodingKeys: String, CodingKey {
                case name, price, position
                case billId = "bill_id"
            }
        }
        let inserts = parsedItems.enumerated().map { idx, item in
            ItemInsert(billId: billId, name: item.name, price: item.price, position: idx)
        }
        return try await supabase
            .from("bill_items")
            .insert(inserts)
            .select()
            .order("position")
            .execute()
            .value
    }
}

enum BillError: Error {
    case notSignedIn
    case createFailed
}
