import Foundation
import Supabase

final class ProfileStatsService {
    static let shared = ProfileStatsService()

    private let supabase = SupabaseManager.shared.client

    private init() {}

    func stats(for profileId: UUID) async throws -> FriendProfileStats {
        let rows: [FriendProfileStats] = try await supabase
            .rpc("get_friend_profile_stats", params: ["p_profile_id": profileId.uuidString])
            .execute()
            .value

        return rows.first ?? FriendProfileStats(totalEvents: 0, onTimeCount: 0, lateCount: 0)
    }
}
