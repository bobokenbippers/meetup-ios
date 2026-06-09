import Foundation

/// Per-user preferences persisted in the `user_settings` table (one row per user,
/// keyed by `user_id` = auth.uid()). Notification + privacy toggles surfaced in Settings.
struct UserSettings: Codable {
    let userId: UUID
    var pushNotificationsEnabled: Bool
    var eventCancelledEnabled: Bool
    var locationSharingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case pushNotificationsEnabled = "push_notifications_enabled"
        case eventCancelledEnabled = "event_cancelled_enabled"
        case locationSharingEnabled = "location_sharing_enabled"
    }
}
