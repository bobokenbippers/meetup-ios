import Foundation
import Supabase

enum GameGroupError: LocalizedError {
    case notSignedIn
    case createFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:  return "You must be signed in to manage groups."
        case .createFailed: return "Couldn't create the group. Try again."
        }
    }
}

/// CRUD for game groups. Membership writes go through SECURITY
/// DEFINER RPCs so the friend gate (only accepted friends of the
/// owner can be added) is enforced server-side.
final class GameGroupService {
    static let shared = GameGroupService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Reads

    /// Groups the current user belongs to (owned or joined), newest
    /// first, with member counts.
    func fetchMyGroups() async throws -> [GameGroup] {
        guard let userId = supabase.auth.currentUser?.id else { throw GameGroupError.notSignedIn }

        struct MembershipRow: Decodable {
            let group: GroupRow?

            struct GroupRow: Decodable {
                let id: UUID
                let name: String
                let ownerId: UUID
                let createdAt: Date
                let members: [CountRow]

                struct CountRow: Decodable {
                    let count: Int
                }

                enum CodingKeys: String, CodingKey {
                    case id, name
                    case ownerId = "owner_id"
                    case createdAt = "created_at"
                    case members = "game_group_members"
                }
            }

            enum CodingKeys: String, CodingKey {
                case group = "game_groups"
            }
        }

        let rows: [MembershipRow] = try await supabase
            .from("game_group_members")
            .select("game_groups!game_group_members_group_id_fkey(id, name, owner_id, created_at, game_group_members(count))")
            .eq("user_id", value: userId)
            .execute()
            .value

        return rows
            .compactMap { $0.group }
            .map {
                GameGroup(
                    id: $0.id,
                    name: $0.name,
                    ownerId: $0.ownerId,
                    createdAt: $0.createdAt,
                    memberCount: $0.members.first?.count
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// All members of a group with their profile for display,
    /// oldest first (owner is always the first member).
    func fetchMembers(groupId: UUID) async throws -> [GameGroupMember] {
        try await supabase
            .from("game_group_members")
            .select("*, profiles!game_group_members_user_id_fkey(display_name, avatar_url)")
            .eq("group_id", value: groupId)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    /// Accepted friends of the current user, for the add-member picker.
    func fetchFriends() async throws -> [Profile] {
        try await MeetupService.shared.getFriends()
    }

    // MARK: - Writes (RPCs)

    func createGroup(name: String) async throws -> UUID {
        struct Params: Encodable {
            let p_name: String
        }
        return try await supabase
            .rpc("create_game_group", params: Params(p_name: name))
            .execute()
            .value
    }

    func addMember(groupId: UUID, userId: UUID) async throws {
        struct Params: Encodable {
            let p_group_id: UUID
            let p_user_id: UUID
        }
        try await supabase
            .rpc("add_game_group_member", params: Params(p_group_id: groupId, p_user_id: userId))
            .execute()
    }

    func removeMember(groupId: UUID, userId: UUID) async throws {
        struct Params: Encodable {
            let p_group_id: UUID
            let p_user_id: UUID
        }
        try await supabase
            .rpc("remove_game_group_member", params: Params(p_group_id: groupId, p_user_id: userId))
            .execute()
    }

    func leaveGroup(groupId: UUID) async throws {
        struct Params: Encodable {
            let p_group_id: UUID
        }
        try await supabase
            .rpc("leave_game_group", params: Params(p_group_id: groupId))
            .execute()
    }

    /// Owner-only (RLS-enforced). Sessions started from the group
    /// survive with group_id set to null.
    func deleteGroup(groupId: UUID) async throws {
        try await supabase
            .from("game_groups")
            .delete()
            .eq("id", value: groupId)
            .execute()
    }
}
