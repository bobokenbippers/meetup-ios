import Foundation
import Supabase

/// Metadata attached to a suggested profile so the UI can display
/// "In your contacts" vs "X mutual friends".
enum SuggestionReason: Equatable {
    case inContacts
    case mutualFriends(Int)
}

struct ProfileSuggestion: Identifiable {
    let profile: Profile
    let reason: SuggestionReason

    var id: UUID { profile.id }
}

final class SuggestionsService {
    static let shared = SuggestionsService()
    private let supabase = SupabaseManager.shared.client

    // MARK: - Public API

    /// Returns a deduplicated, sorted list of suggestions.
    /// Contacts-matched users appear first, then friends-of-friends by mutual count descending.
    func fetchSuggestions(
        contactsManager: ContactsManager,
        existingFriendIds: Set<UUID>
    ) async throws -> [ProfileSuggestion] {
        async let contactMatches = fetchContactMatches(
            contactsManager: contactsManager,
            existingFriendIds: existingFriendIds
        )
        async let fofResults = fetchFriendsOfFriends(existingFriendIds: existingFriendIds)

        let (contacts, fof) = try await (contactMatches, fofResults)

        // Deduplicate: contacts take priority over fof
        var seen = Set<UUID>()
        var results: [ProfileSuggestion] = []

        for suggestion in contacts {
            if seen.insert(suggestion.id).inserted {
                results.append(suggestion)
            }
        }
        for suggestion in fof {
            if seen.insert(suggestion.id).inserted {
                results.append(suggestion)
            }
        }

        return results
    }

    // MARK: - Contact Matches

    /// Looks up profiles whose phone_e164 matches any number from the device contacts,
    /// excluding users already in the friend list and the current user.
    func fetchContactMatches(
        contactsManager: ContactsManager,
        existingFriendIds: Set<UUID>
    ) async throws -> [ProfileSuggestion] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }

        let phones = contactsManager.contacts.flatMap { $0.phones }
        guard !phones.isEmpty else { return [] }

        // Query profiles table for any of these phone numbers
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("phone_e164", values: phones)
            .execute()
            .value

        return profiles
            .filter { $0.id != myId && !existingFriendIds.contains($0.id) }
            .map { ProfileSuggestion(profile: $0, reason: .inContacts) }
    }

    // MARK: - Friends of Friends

    /// Fetches accepted friendships of all the current user's friends,
    /// deduplicates, removes existing friends + self, then attaches mutual-friend count.
    func fetchFriendsOfFriends(
        existingFriendIds: Set<UUID>
    ) async throws -> [ProfileSuggestion] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }
        guard !existingFriendIds.isEmpty else { return [] }

        struct FriendshipRow: Codable {
            let userAId: UUID
            let userBId: UUID
            enum CodingKeys: String, CodingKey {
                case userAId = "user_a_id"
                case userBId = "user_b_id"
            }
        }

        // Fetch all accepted friendships that involve any of our friends
        let friendIdStrings = existingFriendIds.map { $0.uuidString }

        // We need rows where user_a_id OR user_b_id is one of our friends
        // Supabase JS SDK supports `in` on OR arms via two queries — we run both and merge
        let rowsA: [FriendshipRow] = try await supabase
            .from("friendships")
            .select("user_a_id,user_b_id")
            .in("user_a_id", values: friendIdStrings)
            .eq("status", value: "accepted")
            .execute()
            .value

        let rowsB: [FriendshipRow] = try await supabase
            .from("friendships")
            .select("user_a_id,user_b_id")
            .in("user_b_id", values: friendIdStrings)
            .eq("status", value: "accepted")
            .execute()
            .value

        let allRows = rowsA + rowsB

        // Count how many mutual friends each candidate has with us
        var mutualCount: [UUID: Int] = [:]
        for row in allRows {
            // The "other" person in this friendship (relative to our friend)
            let sides = [row.userAId, row.userBId]
            for candidate in sides {
                // Skip self and existing friends
                guard candidate != myId, !existingFriendIds.contains(candidate) else { continue }
                mutualCount[candidate, default: 0] += 1
            }
        }

        guard !mutualCount.isEmpty else { return [] }

        let candidateIds = Array(mutualCount.keys.map { $0.uuidString })
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: candidateIds)
            .execute()
            .value

        return profiles
            .compactMap { profile -> ProfileSuggestion? in
                guard let count = mutualCount[profile.id] else { return nil }
                return ProfileSuggestion(profile: profile, reason: .mutualFriends(count))
            }
            .sorted { lhs, rhs in
                // Sort by mutual friend count descending
                if case .mutualFriends(let a) = lhs.reason,
                   case .mutualFriends(let b) = rhs.reason {
                    return a > b
                }
                return false
            }
    }
}
