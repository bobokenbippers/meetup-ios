import Foundation
import UIKit
import Supabase

enum TruthOrDareError: LocalizedError {
    case notSignedIn
    case compressionFailed
    case flipFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:       return "You must be signed in to play."
        case .compressionFailed: return "Failed to compress the proof photo."
        case .flipFailed:        return "The coin flip didn't reach the server. Try again."
        case .startFailed:       return "Couldn't start the game. Try again."
        }
    }
}

/// All Truth or Dare reads and state transitions. Every game mutation
/// goes through a SECURITY DEFINER RPC so the coin flip, prompt draw,
/// and turn advancement are server-authoritative and identical on
/// every player's device.
final class TruthOrDareService {
    static let shared = TruthOrDareService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    // Dare proofs live in the existing meetup-photos bucket, under a
    // dares/ subfolder, so the bucket's signed-URL policies apply.
    private let bucket = "meetup-photos"
    private let signedURLExpiry = 3600

    // MARK: - Reads

    /// The live (lobby or active) session for a meetup, if any.
    func fetchLiveSession(meetupId: UUID) async throws -> GameSession? {
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("meetup_id", value: meetupId)
            .in("status", values: ["lobby", "active"])
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return sessions.first
    }

    func fetchSession(sessionId: UUID) async throws -> GameSession? {
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("id", value: sessionId)
            .execute()
            .value
        return sessions.first
    }

    /// Look up a session by its invite code. Only resolves for games
    /// the caller can already see (RLS) — joining a new game goes
    /// through `joinSessionByCode` instead.
    func fetchSessionByCode(code: String) async throws -> GameSession? {
        let sessions: [GameSession] = try await supabase
            .from("game_sessions")
            .select()
            .eq("invite_code", value: code.trimmingCharacters(in: .whitespaces).uppercased())
            .execute()
            .value
        return sessions.first
    }

    /// Sessions the current user has joined, newest first, for the
    /// Games tab list.
    func fetchMyGames() async throws -> [MyGameEntry] {
        guard let userId = supabase.auth.currentUser?.id else { throw TruthOrDareError.notSignedIn }
        return try await supabase
            .from("game_players")
            .select("session_id, user_id, joined_at, game_sessions!game_players_session_id_fkey(*)")
            .eq("user_id", value: userId)
            .order("joined_at", ascending: false)
            .limit(20)
            .execute()
            .value
    }

    func fetchPlayers(sessionId: UUID) async throws -> [GamePlayer] {
        try await supabase
            .from("game_players")
            .select("*, profiles!game_players_user_id_fkey(display_name, avatar_url)")
            .eq("session_id", value: sessionId)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    /// All turns for a session, oldest first, with proof photo paths
    /// swapped for fresh signed URLs.
    func fetchTurns(sessionId: UUID) async throws -> [GameTurn] {
        // The FK hint is required: game_turn_votes references both
        // game_turns and profiles, so PostgREST sees two relationships
        // between game_turns and profiles (the direct player FK and a
        // many-to-many through votes) and rejects a bare embed.
        let turns: [GameTurn] = try await supabase
            .from("game_turns")
            .select("*, profiles!game_turns_player_id_fkey(display_name, avatar_url)")
            .eq("session_id", value: sessionId)
            .order("turn_number", ascending: true)
            .execute()
            .value
        return await refreshProofURLs(turns)
    }

    // MARK: - State transitions (RPCs)

    /// Start a standalone session — no meetup required. The returned
    /// invite code is what friends type in to join. Passing a
    /// `groupId` stamps the session with the game group and pushes
    /// the code to every other member.
    func startSession(tier: String, groupId: UUID? = nil) async throws -> StartGameResult {
        struct Params: Encodable {
            let p_tier: String
            let p_group_id: UUID?
        }
        let results: [StartGameResult] = try await supabase
            .rpc("start_truth_or_dare", params: Params(p_tier: tier, p_group_id: groupId))
            .execute()
            .value
        guard let result = results.first else { throw TruthOrDareError.startFailed }
        return result
    }

    /// Start a session embedded in a meetup (legacy flow).
    func startSession(meetupId: UUID, tier: String) async throws -> StartGameResult {
        struct Params: Encodable {
            let p_tier: String
            let p_meetup_id: UUID
        }
        let results: [StartGameResult] = try await supabase
            .rpc("start_truth_or_dare", params: Params(p_tier: tier, p_meetup_id: meetupId))
            .execute()
            .value
        guard let result = results.first else { throw TruthOrDareError.startFailed }
        return result
    }

    /// Join a session by invite code. Returns the session id so the
    /// caller can open the game directly.
    func joinSessionByCode(code: String) async throws -> UUID {
        struct Params: Encodable {
            let p_code: String
        }
        return try await supabase
            .rpc("join_truth_or_dare_by_code",
                 params: Params(p_code: code.trimmingCharacters(in: .whitespaces).uppercased()))
            .execute()
            .value
    }

    func joinSession(sessionId: UUID) async throws {
        try await supabase
            .rpc("join_truth_or_dare", params: ["p_session_id": sessionId])
            .execute()
    }

    func beginGame(sessionId: UUID) async throws {
        try await supabase
            .rpc("begin_truth_or_dare", params: ["p_session_id": sessionId])
            .execute()
    }

    /// Flip the coin for a turn. The server decides heads/tails and
    /// draws the prompt; the returned result is what every other
    /// player will see via Realtime.
    func flipCoin(turnId: UUID) async throws -> CoinFlipResult {
        let results: [CoinFlipResult] = try await supabase
            .rpc("flip_truth_or_dare_coin", params: ["p_turn_id": turnId])
            .execute()
            .value
        guard let result = results.first else { throw TruthOrDareError.flipFailed }
        return result
    }

    /// Mark a turn as done. Dares require `proofPath` (enforced again
    /// server-side).
    func completeTurn(turnId: UUID, proofPath: String?) async throws {
        struct Params: Encodable {
            let p_turn_id: UUID
            let p_action: String
            let p_proof_path: String?
        }
        try await supabase
            .rpc("complete_truth_or_dare_turn",
                 params: Params(p_turn_id: turnId, p_action: "done", p_proof_path: proofPath))
            .execute()
    }

    /// Assign (or override) the dare for the current turn.
    /// Called by any game player who is NOT the doer. Passing the
    /// existing `promptText` keeps the server suggestion; passing a
    /// non-empty string replaces it. The first caller wins — a race
    /// from a second player is silently ignored by the server.
    func assignDare(turnId: UUID, promptText: String) async throws {
        struct Params: Encodable {
            let p_turn_id: UUID
            let p_prompt_text: String
        }
        try await supabase
            .rpc("assign_dare_prompt",
                 params: Params(p_turn_id: turnId, p_prompt_text: promptText))
            .execute()
    }

    /// Chicken out of the current turn.
    func passTurn(turnId: UUID) async throws {
        struct Params: Encodable {
            let p_turn_id: UUID
            let p_action: String
            let p_proof_path: String?
        }
        try await supabase
            .rpc("complete_truth_or_dare_turn",
                 params: Params(p_turn_id: turnId, p_action: "pass", p_proof_path: nil))
            .execute()
    }

    func endSession(sessionId: UUID) async throws {
        try await supabase
            .rpc("end_truth_or_dare", params: ["p_session_id": sessionId])
            .execute()
    }

    // MARK: - Dare proof photos

    /// Compress and upload a dare proof, returning the storage path
    /// to store on the turn row. Meetup games keep their proofs under
    /// the meetup's folder; standalone games use a games/ folder keyed
    /// by session id.
    func uploadProofPhoto(image: UIImage, sessionId: UUID, meetupId: UUID?) async throws -> String {
        guard supabase.auth.currentUser != nil else { throw TruthOrDareError.notSignedIn }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw TruthOrDareError.compressionFailed
        }
        let folder = meetupId.map { "\($0.uuidString)/dares" } ?? "games/\(sessionId.uuidString)/dares"
        let path = "\(folder)/\(UUID().uuidString).jpg"
        try await supabase.storage
            .from(bucket)
            .upload(path: path, file: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        return path
    }

    private func refreshProofURLs(_ turns: [GameTurn]) async -> [GameTurn] {
        var refreshed: [GameTurn] = []
        refreshed.reserveCapacity(turns.count)
        for turn in turns {
            guard let path = turn.proofPhotoUrl, !path.isEmpty else {
                refreshed.append(turn)
                continue
            }
            do {
                let signed = try await supabase.storage
                    .from(bucket)
                    .createSignedURL(path: path, expiresIn: signedURLExpiry)
                refreshed.append(turn.replacingProofPhotoUrl(signed.absoluteString))
            } catch is CancellationError {
                refreshed.append(turn)
            } catch {
                // Leave the raw path; the feed shows a placeholder.
                refreshed.append(turn)
            }
        }
        return refreshed
    }
}
