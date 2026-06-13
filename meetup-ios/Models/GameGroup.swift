import Foundation

/// A persistent named group of friends for playing Truth or Dare
/// together. The owner adds accepted friends as members.
struct GameGroup: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let ownerId: UUID
    let createdAt: Date
    let memberCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case memberCount = "member_count"
    }
}

/// One member of a game group, with the profile fields the roster
/// needs for display.
struct GameGroupMember: Codable, Identifiable, Equatable {
    let groupId: UUID
    let userId: UUID
    let joinedAt: Date
    let profiles: GamePlayer.PlayerProfile?

    enum CodingKeys: String, CodingKey {
        case profiles
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }

    var id: UUID { userId }
    var displayName: String? { profiles?.displayName }
    var avatarUrl: String? { profiles?.avatarUrl }
}
