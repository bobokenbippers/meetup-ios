import Foundation

struct MeetupComment: Codable, Identifiable, Equatable {
    let id: UUID
    let meetupId: UUID
    let authorUserId: UUID
    let body: String
    let createdAt: Date
    let authorDisplayName: String?
    let authorAvatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case meetupId = "meetup_id"
        case authorUserId = "author_user_id"
        case createdAt = "created_at"
        case authorDisplayName = "author_display_name"
        case authorAvatarUrl = "author_avatar_url"
    }
}
