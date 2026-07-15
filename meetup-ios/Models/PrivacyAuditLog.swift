import Foundation

struct PrivacyAuditLog: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let actorId: UUID?
    let meetupId: UUID?
    let eventType: PrivacyAuditEventType
    let metadata: [String: String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case actorId = "actor_id"
        case meetupId = "meetup_id"
        case eventType = "event_type"
        case metadata
        case createdAt = "created_at"
    }
}

enum PrivacyAuditEventType: String, Codable, Equatable {
    case locationSharingStarted = "location_sharing_started"
    case locationSharingStopped = "location_sharing_stopped"
    case locationCleared = "location_cleared"
    case meetupCompleted = "meetup_completed"

    var title: String {
        switch self {
        case .locationSharingStarted:
            return "Location sharing started"
        case .locationSharingStopped:
            return "Location sharing stopped"
        case .locationCleared:
            return "Location cleared"
        case .meetupCompleted:
            return "Meetup completed"
        }
    }

    var systemImage: String {
        switch self {
        case .locationSharingStarted:
            return "location.fill"
        case .locationSharingStopped:
            return "location.slash.fill"
        case .locationCleared:
            return "eye.slash.fill"
        case .meetupCompleted:
            return "checkmark.seal.fill"
        }
    }
}
