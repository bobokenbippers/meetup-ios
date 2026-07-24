import Foundation

struct Receipt: Codable, Identifiable, Equatable {
    let id: UUID
    let meetupId: UUID
    let placeName: String
    let payerUserId: UUID
    var totalAmount: Double
    let tax: Double
    let tip: Double
    let surcharge: Double
    let photoUrl: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, tax, tip, surcharge
        case meetupId    = "meetup_id"
        case placeName   = "place_name"
        case payerUserId = "payer_user_id"
        case totalAmount = "total_amount"
        case photoUrl    = "photo_url"
        case createdAt   = "created_at"
    }

    func replacingPhotoUrl(_ photoUrl: String) -> Receipt {
        Receipt(
            id: id,
            meetupId: meetupId,
            placeName: placeName,
            payerUserId: payerUserId,
            totalAmount: totalAmount,
            tax: tax,
            tip: tip,
            surcharge: surcharge,
            photoUrl: photoUrl,
            createdAt: createdAt
        )
    }
}
