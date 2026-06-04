import Foundation

struct Bill: Codable, Identifiable {
    let id: UUID
    let meetupId: UUID
    let createdBy: UUID
    let subtotal: Double
    let tax: Double
    let tip: Double
    let total: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, subtotal, tax, tip, total
        case meetupId  = "meetup_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct BillItem: Codable, Identifiable {
    let id: UUID
    let billId: UUID
    var name: String
    var price: Double
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, name, price, position
        case billId = "bill_id"
    }
}

struct BillItemClaim: Codable, Identifiable {
    let id: UUID
    let billItemId: UUID
    let userId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case billItemId = "bill_item_id"
        case userId     = "user_id"
        case createdAt  = "created_at"
    }
}
