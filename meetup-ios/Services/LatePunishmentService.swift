import Foundation
import Supabase

final class LatePunishmentService {
    static let shared = LatePunishmentService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    func fetchVotes(meetupId: UUID) async throws -> [LatePunishmentVote] {
        try await supabase
            .from("meetup_late_punishment_votes")
            .select()
            .eq("meetup_id", value: meetupId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func vote(meetupId: UUID, optionKey: String) async throws {
        struct Params: Encodable {
            let pMeetupId: UUID
            let pOptionKey: String

            enum CodingKeys: String, CodingKey {
                case pMeetupId = "p_meetup_id"
                case pOptionKey = "p_option_key"
            }
        }

        try await supabase
            .rpc(
                "vote_late_punishment",
                params: Params(pMeetupId: meetupId, pOptionKey: optionKey)
            )
            .execute()
    }
}
