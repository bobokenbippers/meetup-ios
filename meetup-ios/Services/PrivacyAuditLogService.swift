import Foundation
import Supabase

final class PrivacyAuditLogService {
    static let shared = PrivacyAuditLogService()
    private let supabase = SupabaseManager.shared.client

    private init() {}

    func fetchRecent(limit: Int = 12) async throws -> [PrivacyAuditLog] {
        guard let userId = supabase.auth.currentUser?.id else { return [] }

        return try await supabase
            .from("privacy_audit_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func log(_ eventType: PrivacyAuditEventType, meetup: Meetup) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }

        struct PrivacyAuditLogInsert: Encodable {
            let userId: UUID
            let actorId: UUID
            let meetupId: UUID
            let eventType: PrivacyAuditEventType
            let metadata: [String: String]

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case actorId = "actor_id"
                case meetupId = "meetup_id"
                case eventType = "event_type"
                case metadata
            }
        }

        try await supabase
            .from("privacy_audit_logs")
            .insert(PrivacyAuditLogInsert(
                userId: userId,
                actorId: userId,
                meetupId: meetup.id,
                eventType: eventType,
                metadata: ["destination_name": meetup.destinationName]
            ))
            .execute()
    }
}
