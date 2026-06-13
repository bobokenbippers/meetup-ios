import Foundation

/// A Truth or Dare game session. Standalone sessions have no meetup
/// (`meetupId == nil`) and are joined via their short invite code.
struct GameSession: Codable, Identifiable, Equatable {
    let id: UUID
    let meetupId: UUID?
    let groupId: UUID?
    let startedBy: UUID
    let tier: String                 // "normal" | "spicy"
    let status: String               // "lobby" | "active" | "ended"
    let turnOrder: [UUID]
    let currentTurnIndex: Int
    let inviteCode: String?
    let createdAt: Date
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, tier, status
        case meetupId = "meetup_id"
        case groupId = "group_id"
        case startedBy = "started_by"
        case turnOrder = "turn_order"
        case currentTurnIndex = "current_turn_index"
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case endedAt = "ended_at"
    }

    var isLobby: Bool { status == "lobby" }
    var isActive: Bool { status == "active" }
    var isEnded: Bool { status == "ended" }
    var isSpicy: Bool { tier == "spicy" }
}

/// A player who joined a game session.
struct GamePlayer: Codable, Identifiable, Equatable {
    let sessionId: UUID
    let userId: UUID
    let joinedAt: Date
    let profiles: PlayerProfile?

    struct PlayerProfile: Codable, Equatable {
        let displayName: String?
        let avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarUrl = "avatar_url"
        }
    }

    var id: UUID { userId }
    var displayName: String? { profiles?.displayName }
    var avatarUrl: String? { profiles?.avatarUrl }

    enum CodingKeys: String, CodingKey {
        case profiles
        case sessionId = "session_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

/// One turn in a game session.
///
/// Status lifecycle: `pending` (waiting for coin flip) → `prompted`
/// (coin landed, prompt drawn) → `completed` or `passed`.
///
/// For dare turns, `dareLocked` gates the doer: false = assigning
/// phase (another player picks/edits the dare text); true = dare is
/// set and the doer can act. Truths skip the assigning phase and
/// are always locked immediately after the coin flip.
struct GameTurn: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID
    let turnNumber: Int
    let playerId: UUID
    let status: String
    let coinResult: String?          // "heads" | "tails"
    let promptKind: String?          // "truth" | "dare"
    let promptText: String?
    let proofPhotoUrl: String?
    let dareLocked: Bool             // false = assigning phase; true = dare confirmed
    let createdAt: Date
    let completedAt: Date?
    let profiles: GamePlayer.PlayerProfile?

    enum CodingKeys: String, CodingKey {
        case id, status, profiles
        case sessionId = "session_id"
        case turnNumber = "turn_number"
        case playerId = "player_id"
        case coinResult = "coin_result"
        case promptKind = "prompt_kind"
        case promptText = "prompt_text"
        case proofPhotoUrl = "proof_photo_url"
        case dareLocked = "dare_locked"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    var isPending: Bool { status == "pending" }
    var isPrompted: Bool { status == "prompted" }
    var isCompleted: Bool { status == "completed" }
    var isPassed: Bool { status == "passed" }
    var isTruth: Bool { promptKind == "truth" }
    var isDare: Bool { promptKind == "dare" }
    var playerDisplayName: String? { profiles?.displayName }

    /// Local copy of this turn with the server's flip result applied,
    /// so the flipping player's animation starts before the Realtime
    /// echo arrives. Truths are immediately locked; dares start unlocked.
    func applyingFlip(_ result: CoinFlipResult) -> GameTurn {
        GameTurn(
            id: id,
            sessionId: sessionId,
            turnNumber: turnNumber,
            playerId: playerId,
            status: "prompted",
            coinResult: result.coinResult,
            promptKind: result.promptKind,
            promptText: result.promptText,
            proofPhotoUrl: proofPhotoUrl,
            dareLocked: result.promptKind == "truth",
            createdAt: createdAt,
            completedAt: completedAt,
            profiles: profiles
        )
    }

    func replacingProofPhotoUrl(_ url: String?) -> GameTurn {
        GameTurn(
            id: id,
            sessionId: sessionId,
            turnNumber: turnNumber,
            playerId: playerId,
            status: status,
            coinResult: coinResult,
            promptKind: promptKind,
            promptText: promptText,
            proofPhotoUrl: url,
            dareLocked: dareLocked,
            createdAt: createdAt,
            completedAt: completedAt,
            profiles: profiles
        )
    }
}

/// Result of the start-session RPC: the new session and the short
/// invite code friends use to join it.
struct StartGameResult: Codable, Equatable {
    let sessionId: UUID
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case inviteCode = "invite_code"
    }
}

/// A row in the Games tab list: the caller's membership joined with
/// the session it belongs to.
struct MyGameEntry: Codable, Identifiable, Equatable {
    let sessionId: UUID
    let userId: UUID
    let joinedAt: Date
    let session: GameSession?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case session = "game_sessions"
    }

    var id: UUID { sessionId }
}

/// Result of the server-side coin flip RPC.
struct CoinFlipResult: Codable, Equatable {
    let coinResult: String           // "heads" | "tails"
    let promptKind: String           // "truth" | "dare"
    let promptText: String

    enum CodingKeys: String, CodingKey {
        case coinResult = "coin_result"
        case promptKind = "prompt_kind"
        case promptText = "prompt_text"
    }

    var isTails: Bool { coinResult == "tails" }
}

/// One row of the end-of-game scoreboard.
struct GameScoreEntry: Identifiable, Equatable {
    let playerId: UUID
    let displayName: String
    let completedTruths: Int
    let completedDares: Int
    let passes: Int

    var id: UUID { playerId }
    var completedTotal: Int { completedTruths + completedDares }
}

enum GameScoreboard {
    /// Tally completed truths/dares and passes per player. Sorted by
    /// most completed, fewest passes; chickens sink to the bottom.
    static func compute(players: [GamePlayer], turns: [GameTurn]) -> [GameScoreEntry] {
        var entries: [UUID: (truths: Int, dares: Int, passes: Int)] = [:]
        for player in players {
            entries[player.userId] = (0, 0, 0)
        }
        for turn in turns {
            var entry = entries[turn.playerId] ?? (0, 0, 0)
            if turn.isCompleted {
                if turn.isDare { entry.dares += 1 } else { entry.truths += 1 }
            } else if turn.isPassed {
                entry.passes += 1
            }
            entries[turn.playerId] = entry
        }

        func name(for userId: UUID) -> String {
            players.first(where: { $0.userId == userId })?.displayName
                ?? turns.first(where: { $0.playerId == userId })?.playerDisplayName
                ?? "Player"
        }

        return entries
            .map { userId, tally in
                GameScoreEntry(
                    playerId: userId,
                    displayName: name(for: userId),
                    completedTruths: tally.truths,
                    completedDares: tally.dares,
                    passes: tally.passes
                )
            }
            .sorted {
                if $0.completedTotal != $1.completedTotal { return $0.completedTotal > $1.completedTotal }
                if $0.passes != $1.passes { return $0.passes < $1.passes }
                return $0.displayName < $1.displayName
            }
    }
}
