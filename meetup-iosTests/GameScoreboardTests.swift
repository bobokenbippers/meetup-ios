import Testing
import Foundation
@testable import meetup_ios

@Suite("GameScoreboard.compute")
struct GameScoreboardTests {

    private let sessionId = UUID()

    private func makePlayer(userId: UUID, name: String) -> GamePlayer {
        GamePlayer(
            sessionId: sessionId,
            userId: userId,
            joinedAt: Date(),
            profiles: .init(displayName: name, avatarUrl: nil)
        )
    }

    private func makeTurn(
        player: UUID,
        number: Int,
        status: String,
        kind: String?
    ) -> GameTurn {
        GameTurn(
            id: UUID(),
            sessionId: sessionId,
            turnNumber: number,
            playerId: player,
            status: status,
            coinResult: kind == "truth" ? "heads" : (kind == "dare" ? "tails" : nil),
            promptKind: kind,
            promptText: kind == nil ? nil : "prompt",
            proofPhotoUrl: nil,
            createdAt: Date(),
            completedAt: status == "completed" || status == "passed" ? Date() : nil,
            profiles: nil
        )
    }

    @Test("tallies truths, dares, and passes per player")
    func tallies() throws {
        let alice = UUID()
        let bob = UUID()
        let players = [makePlayer(userId: alice, name: "Alice"), makePlayer(userId: bob, name: "Bob")]
        let turns = [
            makeTurn(player: alice, number: 1, status: "completed", kind: "truth"),
            makeTurn(player: bob, number: 2, status: "completed", kind: "dare"),
            makeTurn(player: alice, number: 3, status: "completed", kind: "dare"),
            makeTurn(player: bob, number: 4, status: "passed", kind: "truth"),
        ]

        let board = GameScoreboard.compute(players: players, turns: turns)
        let aliceEntry = try #require(board.first(where: { $0.playerId == alice }))
        let bobEntry = try #require(board.first(where: { $0.playerId == bob }))

        #expect(aliceEntry.completedTruths == 1)
        #expect(aliceEntry.completedDares == 1)
        #expect(aliceEntry.passes == 0)
        #expect(bobEntry.completedTruths == 0)
        #expect(bobEntry.completedDares == 1)
        #expect(bobEntry.passes == 1)
    }

    @Test("ranks by completions, then fewest passes")
    func ranking() {
        let a = UUID(), b = UUID(), c = UUID()
        let players = [
            makePlayer(userId: a, name: "A"),
            makePlayer(userId: b, name: "B"),
            makePlayer(userId: c, name: "C"),
        ]
        let turns = [
            makeTurn(player: a, number: 1, status: "completed", kind: "truth"),
            makeTurn(player: b, number: 2, status: "completed", kind: "dare"),
            makeTurn(player: b, number: 3, status: "completed", kind: "truth"),
            makeTurn(player: c, number: 4, status: "completed", kind: "truth"),
            makeTurn(player: c, number: 5, status: "passed", kind: "dare"),
        ]

        let board = GameScoreboard.compute(players: players, turns: turns)
        #expect(board.map(\.playerId) == [b, a, c])
    }

    @Test("ignores open turns and includes turnless players")
    func openTurnsAndIdlePlayers() {
        let a = UUID(), b = UUID()
        let players = [makePlayer(userId: a, name: "A"), makePlayer(userId: b, name: "B")]
        let turns = [
            makeTurn(player: a, number: 1, status: "completed", kind: "dare"),
            makeTurn(player: b, number: 2, status: "pending", kind: nil),
        ]

        let board = GameScoreboard.compute(players: players, turns: turns)
        #expect(board.count == 2)
        let bEntry = board.first(where: { $0.playerId == b })
        #expect(bEntry?.completedTotal == 0)
        #expect(bEntry?.passes == 0)
    }

    @Test("counts players known only from turns")
    func playerOnlyInTurns() {
        let ghost = UUID()
        let turns = [makeTurn(player: ghost, number: 1, status: "passed", kind: "truth")]

        let board = GameScoreboard.compute(players: [], turns: turns)
        #expect(board.count == 1)
        #expect(board.first?.passes == 1)
        #expect(board.first?.displayName == "Player")
    }
}
