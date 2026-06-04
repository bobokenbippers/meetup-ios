import Foundation

struct Receipt: Codable, Identifiable, Equatable {
    let id: UUID
    let meetupId: UUID
    let placeName: String
    let payerUserId: UUID
    var totalAmount: Double
    let photoUrl: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case meetupId    = "meetup_id"
        case placeName   = "place_name"
        case payerUserId = "payer_user_id"
        case totalAmount = "total_amount"
        case photoUrl    = "photo_url"
        case createdAt   = "created_at"
    }
}
