import Foundation

struct LatePunishmentVote: Codable, Identifiable, Equatable {
    let meetupId: UUID
    let voterId: UUID
    let optionKey: String
    let createdAt: Date

    var id: String { "\(meetupId.uuidString)-\(voterId.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case meetupId = "meetup_id"
        case voterId = "voter_id"
        case optionKey = "option_key"
        case createdAt = "created_at"
    }
}
