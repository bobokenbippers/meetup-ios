import Foundation
import Supabase

/// CRUD for the `user_settings` table. Mirrors `location_sharing_enabled` into
/// UserDefaults so `LocationManager`/dashboard gating can read it synchronously
/// without an async round-trip.
final class UserSettingsService {
    static let shared = UserSettingsService()
    private let supabase = SupabaseManager.shared.client

    /// UserDefaults mirror of the location-sharing preference (default: enabled).
    static let locationSharingKey = "locationSharingEnabled"

    /// Synchronous read of the location-sharing preference for gating live tracking.
    /// Defaults to `true` when no preference has been stored yet.
    static var locationSharingEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: locationSharingKey) == nil ? true : d.bool(forKey: locationSharingKey)
    }

    /// Fetch the current user's settings row, or `nil` if none exists yet.
    func fetch() async throws -> UserSettings? {
        guard let userId = supabase.auth.currentUser?.id else { return nil }
        let rows: [UserSettings] = try await supabase
            .from("user_settings")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        if let settings = rows.first {
            UserDefaults.standard.set(settings.locationSharingEnabled, forKey: Self.locationSharingKey)
        }
        return rows.first
    }

    /// Upsert the current user's settings row.
    func save(_ settings: UserSettings) async throws {
        struct Upsert: Encodable {
            let userId: String
            let pushNotificationsEnabled: Bool
            let eventCancelledEnabled: Bool
            let locationSharingEnabled: Bool
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case pushNotificationsEnabled = "push_notifications_enabled"
                case eventCancelledEnabled = "event_cancelled_enabled"
                case locationSharingEnabled = "location_sharing_enabled"
            }
        }
        try await supabase
            .from("user_settings")
            .upsert(
                Upsert(
                    userId: settings.userId.uuidString,
                    pushNotificationsEnabled: settings.pushNotificationsEnabled,
                    eventCancelledEnabled: settings.eventCancelledEnabled,
                    locationSharingEnabled: settings.locationSharingEnabled
                ),
                onConflict: "user_id"
            )
            .execute()
        UserDefaults.standard.set(settings.locationSharingEnabled, forKey: Self.locationSharingKey)
    }
}
