import Foundation
import Supabase

struct FoundUser {
    let id: UUID
    let displayName: String
    let phone: String
}

enum MeetupError: LocalizedError {
    case notSignedIn
    case createFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You must be signed in"
        case .createFailed: return "Failed to create meetup"
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
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case phoneE164 = "phone_e164"
            }
        }
        let rows: [Row] = try await supabase
            .rpc("find_user_by_email", params: ["search_email": email])
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return FoundUser(id: row.id, displayName: row.displayName ?? "Unknown", phone: row.phoneE164 ?? "")
    }

    func findUserByPhone(_ phone: String) async throws -> FoundUser? {
        struct Row: Codable {
            let id: UUID
            let displayName: String?
            let phoneE164: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case phoneE164 = "phone_e164"
            }
        }
        let rows: [Row] = try await supabase
            .rpc("find_user_by_phone", params: ["search_phone": phone])
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return FoundUser(id: row.id, displayName: row.displayName ?? "Unknown", phone: row.phoneE164 ?? phone)
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

        var participants = [ParticipantInsert(
            meetupId: meetupId,
            userId: hostId,
            status: "yes",
            joinedAt: iso.string(from: Date())
        )]
        for invitee in invitees {
            participants.append(ParticipantInsert(
                meetupId: meetupId,
                userId: invitee.id,
                status: "invited",
                joinedAt: nil
            ))
        }
        try await supabase.from("meetup_participants").insert(participants).execute()
        return meetupId
    }

    func listMyParticipations() async throws -> [MyParticipation] {
        guard let myId = supabase.auth.currentUser?.id else { return [] }
        return try await supabase
            .from("meetup_participants")
            .select("status, meetups(*)")
            .eq("user_id", value: myId)
            .execute()
            .value
    }

    func listParticipants(meetupId: UUID) async throws -> [MeetupParticipant] {
        return try await supabase
            .from("meetup_participants")
            .select("*, profiles(display_name, phone_e164)")
            .eq("meetup_id", value: meetupId)
            .execute()
            .value
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
    }

    func decline(meetupId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("meetup_participants")
            .update(["status": "no"])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
    }

    func maybe(meetupId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("meetup_participants")
            .update(["status": "maybe"])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
    }

    func updateParticipantStatus(meetupId: UUID, status: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
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
        try await supabase
            .from("friendships")
            .delete()
            .eq("user_a_id", value: myId)
            .eq("user_b_id", value: userId)
            .execute()
        try await supabase
            .from("friendships")
            .delete()
            .eq("user_a_id", value: userId)
            .eq("user_b_id", value: myId)
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
}
