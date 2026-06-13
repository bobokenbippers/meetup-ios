import Foundation

struct LatePunishmentProof: Codable, Identifiable, Equatable {
    let id: UUID
    let meetupId: UUID
    let uploaderUserId: UUID
    let photoUrl: String
    let caption: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case meetupId = "meetup_id"
        case uploaderUserId = "uploader_user_id"
        case photoUrl = "photo_url"
        case caption
        case createdAt = "created_at"
    }

    func replacingPhotoUrl(_ url: String) -> LatePunishmentProof {
        LatePunishmentProof(
            id: id,
            meetupId: meetupId,
            uploaderUserId: uploaderUserId,
            photoUrl: url,
            caption: caption,
            createdAt: createdAt
        )
    }
}

struct LatePunishmentProofReactionSummary: Codable, Identifiable, Equatable {
    var id: String { "\(proofId.uuidString)-\(emoji)" }

    let proofId: UUID
    let emoji: String
    let reactionCount: Int
    let reactedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case proofId = "proof_id"
        case emoji
        case reactionCount = "reaction_count"
        case reactedByMe = "reacted_by_me"
    }
}
