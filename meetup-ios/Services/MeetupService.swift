import Foundation
import Supabase

struct FoundUser {
    let id: UUID
    let displayName: String
    let phone: String
    let avatarUrl: String?
}

/// Friendship relationship between the current user and another user.
/// Drives whether someone can be invited directly or must be friend-requested first.
enum FriendshipStatus: Equatable {
    case none             // no friendship row — must send a request before inviting
    case accepted         // accepted friends — invitable
    case pendingOutgoing  // I sent a request, awaiting their acceptance
    case pendingIncoming  // they sent me a request, I can accept it
}

enum MeetupError: LocalizedError {
    case notSignedIn
    case createFailed
    case meetupNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You must be signed in"
        case .createFailed: return "Failed to create meetup"
        case .meetupNotFound: return "Invite link is invalid or expired"
        }
    }
}

final class MeetupService {
    static let shared = MeetupService()
    private let supabase = SupabaseManager.shared.client

    func findUserByEmail(_ email: String) async throws -> FoundUser? {
        struct Row: Codable {
            let id: UUID
            let displayName: String?
            let phoneE164: String?
            let avatarUrl: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case phoneE164 = "phone_e164"
                case avatarUrl = "avatar_url"
            }
        }
        let rows: [Row] = try await supabase
            .rpc("find_user_by_email", params: ["search_email": email])
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return FoundUser(
            id: row.id,
            displayName: row.displayName ?? "Unknown",
            phone: row.phoneE164 ?? "",
            avatarUrl: row.avatarUrl
        )
    }

    func findUserByPhone(_ phone: String) async throws -> FoundUser? {
        struct Row: Codable {
            let id: UUID
            let displayName: String?
            let phoneE164: String?
            let avatarUrl: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case phoneE164 = "phone_e164"
                case avatarUrl = "avatar_url"
            }
        }
        let rows: [Row] = try await supabase
            .rpc("find_user_by_phone", params: ["search_phone": phone])
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return FoundUser(
            id: row.id,
            displayName: row.displayName ?? "Unknown",
            phone: row.phoneE164 ?? phone,
            avatarUrl: row.avatarUrl
        )
    }

    func createMeetup(
        destinationName: String,
        destinationAddress: String?,
        lat: Double,
        lng: Double,
        targetArrivalAt: Date?,
        category: String?,
        invitees: [FoundUser]
    ) async throws -> UUID {
        guard let hostId = supabase.auth.currentUser?.id else { throw MeetupError.notSignedIn }

        struct MeetupInsert: Encodable {
            let hostId: UUID
            let destinationName: String
            let destinationAddress: String?
            let destinationLat: Double
            let destinationLng: Double
            let targetArrivalAt: String?
            let category: String?
            enum CodingKeys: String, CodingKey {
                case hostId = "host_id"
                case destinationName = "destination_name"
                case destinationAddress = "destination_address"
                case destinationLat = "destination_lat"
                case destinationLng = "destination_lng"
                case targetArrivalAt = "target_arrival_at"
                case category
            }
        }

        let iso = ISO8601DateFormatter()
        let meetupInsert = MeetupInsert(
            hostId: hostId,
            destinationName: destinationName,
            destinationAddress: destinationAddress,
            destinationLat: lat,
            destinationLng: lng,
            targetArrivalAt: targetArrivalAt.map { iso.string(from: $0) },
            category: category
        )

        let inserted: [Meetup] = try await supabase
            .from("meetups")
            .insert(meetupInsert)
            .select()
            .execute()
            .value
        guard let meetupId = inserted.first?.id else { throw MeetupError.createFailed }

        struct ParticipantInsert: Encodable {
            let meetupId: UUID
            let userId: UUID
            let status: String
            let joinedAt: String?
            enum CodingKeys: String, CodingKey {
                case meetupId = "meetup_id"
                case userId = "user_id"
                case status
                case joinedAt = "joined_at"
            }
        }

        // Insert the host's own participant row on its own. It always satisfies the
        // friendship-gate RLS (`participants_insert`) because user_id == auth.uid().
        // Keeping it separate from the invitees guarantees a rejected invitee can
        // never roll it back — an orphaned meetup with no host row is invisible to
        // everyone, including the host.
        try await supabase
            .from("meetup_participants")
            .insert(ParticipantInsert(
                meetupId: meetupId,
                userId: hostId,
                status: "yes",
                joinedAt: iso.string(from: Date())
            ))
            .execute()

        // Insert invitees one at a time rather than as a single atomic batch. The
        // friendship gate rejects any invitee who isn't an accepted friend; in a
        // batch that one rejection rolls back the whole insert (host row + every
        // other invite), so legitimate invites never reach their recipients. Per-row
        // inserts isolate each invitee so valid invites still land and surface.
        for invitee in invitees {
            do {
                try await supabase
                    .from("meetup_participants")
                    .insert(ParticipantInsert(
                        meetupId: meetupId,
                        userId: invitee.id,
                        status: "invited",
                        joinedAt: nil
                    ))
                    .execute()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return meetupId
    }

    func listMyParticipations() async throws -> [MyParticipation] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }
        return try await supabase
            .from("meetup_participants")
            .select("status, meetups(*, host_profile:profiles!meetups_host_id_fkey(id, display_name, phone_e164, email, avatar_url))")
            .eq("user_id", value: myId)
            .execute()
            .value
    }

    func listParticipants(meetupId: UUID) async throws -> [MeetupParticipant] {
        struct ParticipantRow: Codable {
            let meetupId: UUID
            let userId: UUID
            let status: String
            let lat: Double?
            let lng: Double?
            let bearing: Double?
            let etaSeconds: Int?
            let locationUpdatedAt: Date?
            let displayName: String?
            let phoneE164: String?
            let avatarUrl: String?

            enum CodingKeys: String, CodingKey {
                case meetupId = "meetup_id"
                case userId = "user_id"
                case status
                case lat, lng, bearing
                case etaSeconds = "eta_seconds"
                case locationUpdatedAt = "location_updated_at"
                case displayName = "display_name"
                case phoneE164 = "phone_e164"
                case avatarUrl = "avatar_url"
            }
        }

        let rows: [ParticipantRow] = try await supabase
            .rpc("list_meetup_participants", params: ["p_meetup_id": meetupId.uuidString])
            .execute()
            .value

        return rows.map { row in
            MeetupParticipant(
                meetupId: row.meetupId,
                userId: row.userId,
                status: row.status,
                lat: row.lat,
                lng: row.lng,
                bearing: row.bearing,
                etaSeconds: row.etaSeconds,
                locationUpdatedAt: row.locationUpdatedAt,
                profiles: MeetupParticipant.ParticipantProfile(
                    displayName: row.displayName,
                    phoneE164: row.phoneE164,
                    avatarUrl: row.avatarUrl
                )
            )
        }
    }

    func accept(meetupId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        let iso = ISO8601DateFormatter()
        try await supabase
            .from("meetup_participants")
            .update(["status": "yes", "joined_at": iso.string(from: Date())])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
        Task { try? await fireRSVPPush(meetupId: meetupId, userId: userId, newStatus: "yes") }
    }

    func decline(meetupId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("meetup_participants")
            .update(["status": "no"])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
        Task { try? await fireRSVPPush(meetupId: meetupId, userId: userId, newStatus: "no") }
    }

    func maybe(meetupId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("meetup_participants")
            .update(["status": "maybe"])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
        Task { try? await fireRSVPPush(meetupId: meetupId, userId: userId, newStatus: "maybe") }
    }

    func updateParticipantStatus(meetupId: UUID, status: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        if status == "arrived" {
            struct ArrivedStatusUpdate: Encodable {
                let status: String
                let arrivedAt: String

                enum CodingKeys: String, CodingKey {
                    case status
                    case arrivedAt = "arrived_at"
                }
            }

            try await supabase
                .from("meetup_participants")
                .update(ArrivedStatusUpdate(
                    status: status,
                    arrivedAt: ISO8601DateFormatter().string(from: Date())
                ))
                .eq("meetup_id", value: meetupId)
                .eq("user_id", value: userId)
                .execute()
            return
        }

        try await supabase
            .from("meetup_participants")
            .update(["status": status])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
    }

    func cancelMeetup(meetupId: UUID) async throws {
        try await supabase
            .from("meetups")
            .update(["status": "cancelled"])
            .eq("id", value: meetupId)
            .execute()
    }

    /// Update a meetup's destination. Name/address/coordinates move together so the map
    /// pin and directions stay consistent with the place selected at creation.
    /// RLS ("host can update meetups") restricts this to the host. Returns the updated row.
    func updateDestination(
        meetupId: UUID,
        destinationName: String,
        destinationAddress: String?,
        lat: Double,
        lng: Double
    ) async throws -> Meetup {
        struct DestinationUpdate: Encodable {
            let destinationName: String
            let destinationAddress: String?
            let destinationLat: Double
            let destinationLng: Double
            enum CodingKeys: String, CodingKey {
                case destinationName = "destination_name"
                case destinationAddress = "destination_address"
                case destinationLat = "destination_lat"
                case destinationLng = "destination_lng"
            }
        }

        let updated: [Meetup] = try await supabase
            .from("meetups")
            .update(DestinationUpdate(
                destinationName: destinationName,
                destinationAddress: destinationAddress,
                destinationLat: lat,
                destinationLng: lng
            ))
            .eq("id", value: meetupId)
            .select()
            .execute()
            .value
        guard let meetup = updated.first else { throw MeetupError.meetupNotFound }
        return meetup
    }

    /// Update a meetup's scheduled time (target arrival). The push-leave-now and
    /// expire-meetups cron functions read target_arrival_at live, so they pick up the
    /// new time automatically — no client-side rescheduling, same as the creation flow.
    /// RLS ("host can update meetups") restricts this to the host. Returns the updated row.
    func updateTargetArrival(meetupId: UUID, targetArrivalAt: Date) async throws -> Meetup {
        struct TargetArrivalUpdate: Encodable {
            let targetArrivalAt: String
            enum CodingKeys: String, CodingKey {
                case targetArrivalAt = "target_arrival_at"
            }
        }

        let iso = ISO8601DateFormatter()
        let updated: [Meetup] = try await supabase
            .from("meetups")
            .update(TargetArrivalUpdate(targetArrivalAt: iso.string(from: targetArrivalAt)))
            .eq("id", value: meetupId)
            .select()
            .execute()
            .value
        guard let meetup = updated.first else { throw MeetupError.meetupNotFound }
        return meetup
    }

    func updateMyLocation(meetupId: UUID, lat: Double, lng: Double, bearing: Double?, etaSeconds: Int?) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }

        struct LocationUpdate: Encodable {
            let lat: Double
            let lng: Double
            let bearing: Double?
            let etaSeconds: Int?
            let locationUpdatedAt: String
            enum CodingKeys: String, CodingKey {
                case lat, lng, bearing
                case etaSeconds = "eta_seconds"
                case locationUpdatedAt = "location_updated_at"
            }
        }

        try await supabase
            .from("meetup_participants")
            .update(LocationUpdate(
                lat: lat,
                lng: lng,
                bearing: bearing,
                etaSeconds: etaSeconds,
                locationUpdatedAt: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
    }

    func getFriends() async throws -> [Profile] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }
        struct FriendshipRow: Codable {
            let userAId: UUID
            let userBId: UUID
            enum CodingKeys: String, CodingKey {
                case userAId = "user_a_id"
                case userBId = "user_b_id"
            }
        }
        let rows: [FriendshipRow] = try await supabase
            .from("friendships")
            .select("user_a_id,user_b_id")
            .or("user_a_id.eq.\(myId),user_b_id.eq.\(myId)")
            .eq("status", value: "accepted")
            .execute()
            .value
        let ids = rows.map { $0.userAId == myId ? $0.userBId : $0.userAId }
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .from("profiles")
            .select()
            .in("id", values: ids.map { $0.uuidString })
            .execute()
            .value
    }

    /// Current friendship relationship between the signed-in user and `userId`.
    /// Used by the invite flows to gate direct adds behind an accepted friendship.
    func friendshipStatus(with userId: UUID) async throws -> FriendshipStatus {
        guard let myId = supabase.auth.currentUser?.id else { return .none }
        let (userAId, userBId) = myId.uuidString < userId.uuidString
            ? (myId, userId)
            : (userId, myId)
        struct Row: Codable {
            let status: String
            let initiatedBy: UUID
            enum CodingKeys: String, CodingKey {
                case status
                case initiatedBy = "initiated_by"
            }
        }
        let rows: [Row] = try await supabase
            .from("friendships")
            .select("status,initiated_by")
            .eq("user_a_id", value: userAId.uuidString)
            .eq("user_b_id", value: userBId.uuidString)
            .execute()
            .value
        guard let row = rows.first else { return .none }
        if row.status == "accepted" { return .accepted }
        if row.status == "pending" {
            return row.initiatedBy == myId ? .pendingOutgoing : .pendingIncoming
        }
        return .none
    }

    func getPendingIncomingRequests() async throws -> [IncomingFriendRequest] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }
        struct Row: Codable {
            let id: UUID
            let initiatedBy: UUID
            enum CodingKeys: String, CodingKey {
                case id
                case initiatedBy = "initiated_by"
            }
        }
        let rows: [Row] = try await supabase
            .from("friendships")
            .select("id,initiated_by")
            .or("user_a_id.eq.\(myId),user_b_id.eq.\(myId)")
            .eq("status", value: "pending")
            .neq("initiated_by", value: myId.uuidString)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: rows.map { $0.initiatedBy.uuidString })
            .execute()
            .value
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return rows.compactMap { row in
            guard let profile = profileMap[row.initiatedBy] else { return nil }
            return IncomingFriendRequest(id: row.id, requester: profile)
        }
    }

    func getPendingOutgoingRequests() async throws -> [PendingOutgoingRequest] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }
        struct Row: Codable {
            let id: UUID
            let userAId: UUID
            let userBId: UUID
            let initiatedBy: UUID
            enum CodingKeys: String, CodingKey {
                case id
                case userAId = "user_a_id"
                case userBId = "user_b_id"
                case initiatedBy = "initiated_by"
            }
        }
        let rows: [Row] = try await supabase
            .from("friendships")
            .select("id,user_a_id,user_b_id,initiated_by")
            .or("user_a_id.eq.\(myId),user_b_id.eq.\(myId)")
            .eq("status", value: "pending")
            .eq("initiated_by", value: myId.uuidString)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }
        let addresseeIds = rows.map { row -> String in
            (row.initiatedBy == row.userAId ? row.userBId : row.userAId).uuidString
        }
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: addresseeIds)
            .execute()
            .value
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return rows.compactMap { row -> PendingOutgoingRequest? in
            let addresseeId = row.initiatedBy == row.userAId ? row.userBId : row.userAId
            guard let profile = profileMap[addresseeId] else { return nil }
            return PendingOutgoingRequest(id: row.id, addressee: profile)
        }
    }

    func acceptFriendRequest(friendshipId: UUID) async throws {
        try await supabase
            .from("friendships")
            .update(["status": "accepted"])
            .eq("id", value: friendshipId.uuidString)
            .execute()
    }

    func declineFriendRequest(friendshipId: UUID) async throws {
        try await supabase
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString)
            .execute()
    }

    func getPeopleFromMeetups() async throws -> [Profile] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }

        let participations = try await listMyParticipations()

        var userIds = Set<UUID>()
        for p in participations {
            let participants = try await listParticipants(meetupId: p.meetup.id)
            for participant in participants {
                if participant.userId != myId {
                    userIds.insert(participant.userId)
                }
            }
        }

        guard !userIds.isEmpty else { return [] }

        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: Array(userIds))
            .execute()
            .value

        return profiles.sorted { ($0.displayName ?? "Unknown") < ($1.displayName ?? "Unknown") }
    }

    func addFriend(userId: UUID) async throws {
        guard let myId = supabase.auth.currentUser?.id else { throw MeetupError.notSignedIn }

        // Canonical ordering required by DB check constraint: user_a_id < user_b_id
        let (userAId, userBId) = myId.uuidString < userId.uuidString
            ? (myId, userId)
            : (userId, myId)

        struct ExistingRow: Codable {
            let id: UUID
            let initiatedBy: UUID
            let status: String
            enum CodingKeys: String, CodingKey {
                case id
                case initiatedBy = "initiated_by"
                case status
            }
        }
        let existing: [ExistingRow] = try await supabase
            .from("friendships")
            .select("id,initiated_by,status")
            .eq("user_a_id", value: userAId.uuidString)
            .eq("user_b_id", value: userBId.uuidString)
            .execute()
            .value

        if let row = existing.first {
            if row.status == "accepted" { return }
            if row.initiatedBy != myId {
                // The other person already sent us a request — accept it
                try await acceptFriendRequest(friendshipId: row.id)
            }
            // If we're already the initiator and it's pending, nothing to do
            return
        }

        struct FriendshipInsert: Encodable {
            let userAId: UUID
            let userBId: UUID
            let status: String
            let initiatedBy: UUID
            enum CodingKeys: String, CodingKey {
                case userAId = "user_a_id"
                case userBId = "user_b_id"
                case status
                case initiatedBy = "initiated_by"
            }
        }

        try await supabase
            .from("friendships")
            .insert(FriendshipInsert(
                userAId: userAId,
                userBId: userBId,
                status: "pending",
                initiatedBy: myId
            ))
            .execute()
    }

    func removeFriend(userId: UUID) async throws {
        guard let myId = supabase.auth.currentUser?.id else { throw MeetupError.notSignedIn }
        let (userAId, userBId) = myId.uuidString < userId.uuidString
            ? (myId, userId)
            : (userId, myId)
        try await supabase
            .from("friendships")
            .delete()
            .eq("user_a_id", value: userAId)
            .eq("user_b_id", value: userBId)
            .execute()
    }

    func restoreMeetup(meetupId: UUID) async throws {
        try await supabase
            .from("meetups")
            .update(["status": "active"])
            .eq("id", value: meetupId)
            .execute()
    }

    func restoreParticipation(meetupId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("meetup_participants")
            .update(["status": "invited"])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Share token

    func fetchMeetupByShareToken(_ token: String) async throws -> Meetup {
        let rows: [Meetup] = try await supabase
            .from("meetups")
            .select()
            .eq("share_token", value: token)
            .limit(1)
            .execute()
            .value
        guard let meetup = rows.first else { throw MeetupError.meetupNotFound }
        return meetup
    }

    /// Returns the existing share token or generates, persists, and returns a new one.
    func ensureShareToken(for meetup: Meetup) async throws -> String {
        if let token = meetup.shareToken, !token.isEmpty { return token }
        let newToken = UUID().uuidString
        struct TokenUpdate: Encodable {
            let shareToken: String
            enum CodingKeys: String, CodingKey {
                case shareToken = "share_token"
            }
        }
        try await supabase
            .from("meetups")
            .update(TokenUpdate(shareToken: newToken))
            .eq("id", value: meetup.id)
            .execute()
        return newToken
    }

    // MARK: - Push helpers

    private func fireRSVPPush(meetupId: UUID, userId: UUID, newStatus: String) async throws {
        let url = URL(string: "https://boyrqhbdkqzffvfokpri.supabase.co/functions/v1/push-rsvp-update")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = try await supabase.auth.session.accessToken
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = [
            "meetupId": meetupId.uuidString,
            "userId": userId.uuidString,
            "newStatus": newStatus,
        ]
        request.httpBody = try JSONEncoder().encode(body)
        _ = try await URLSession.shared.data(for: request)
    }

    /// Invite a user to an existing meetup; no-op if they're already a participant.
    func inviteParticipant(meetupId: UUID, userId: UUID) async throws {
        struct ExistingCheck: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey { case userId = "user_id" }
        }
        let existing: [ExistingCheck] = try await supabase
            .from("meetup_participants")
            .select("user_id")
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
            .value
        if !existing.isEmpty { return }

        struct ParticipantInsert: Encodable {
            let meetupId: UUID
            let userId: UUID
            let status: String
            enum CodingKeys: String, CodingKey {
                case meetupId = "meetup_id"
                case userId = "user_id"
                case status
            }
        }
        try await supabase
            .from("meetup_participants")
            .insert(ParticipantInsert(meetupId: meetupId, userId: userId, status: "invited"))
            .execute()
    }

    /// Join a meetup via share link. The RPC validates the share token server-side
    /// and performs the insert with the right RLS context.
    func joinByShareToken(_ token: String) async throws {
        guard supabase.auth.currentUser?.id != nil else { throw MeetupError.notSignedIn }
        _ = try await supabase
            .rpc("join_meetup_by_token", params: ["p_share_token": token])
            .execute()
    }
}
