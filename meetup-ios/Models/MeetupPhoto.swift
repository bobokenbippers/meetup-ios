import Foundation

struct MeetupPhoto: Codable, Identifiable {
    let id: UUID
    let meetupId: UUID
    let uploaderUserId: UUID
    let photoUrl: String
    let caption: String?
    let createdAt: Date

    // Joined from profiles table
    let profiles: UploaderProfile?

    struct UploaderProfile: Codable {
        let displayName: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    /// Convenience accessor for the uploader's display name.
    var uploaderDisplayName: String? { profiles?.displayName }

    enum CodingKeys: String, CodingKey {
        case id, caption, profiles
        case meetupId = "meetup_id"
        case uploaderUserId = "uploader_user_id"
        case photoUrl = "photo_url"
        case createdAt = "created_at"
    }
}

/// Lightweight row used for inserting into meetup_photos.
struct MeetupPhotoInsert: Encodable {
    let meetupId: UUID
    let uploaderUserId: UUID
    let photoUrl: String
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case meetupId = "meetup_id"
        case uploaderUserId = "uploader_user_id"
        case photoUrl = "photo_url"
        case caption
    }
}
