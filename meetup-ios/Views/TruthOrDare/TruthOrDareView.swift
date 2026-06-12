import SwiftUI
import PhotosUI
import Supabase
import UIKit

/// Truth or Dare game screen. Handles the whole session lifecycle:
/// setup (tier pick), lobby, live game (coin flip → prompt →
/// proof/answer/pass), and the end-of-game scoreboard. All game
/// state is server-authoritative and synced over Supabase Realtime.
///
/// Runs in two modes: standalone (the default — friends join with
/// the session's invite code) or embedded in a meetup, where any
/// meetup participant can play.
struct TruthOrDareView: View {
    let meetup: Meetup?

    /// Standalone mode: open an existing session directly, or start
    /// from the tier-pick setup screen when nil.
    init(sessionId: UUID? = nil) {
        self.meetup = nil
        self._standaloneSessionId = State(initialValue: sessionId)
        self.channelScope = sessionId?.uuidString ?? UUID().uuidString
    }

    /// Meetup-embedded mode: shows the meetup's live game, if any.
    init(meetup: Meetup) {
        self.meetup = meetup
        self._standaloneSessionId = State(initialValue: nil)
        self.channelScope = meetup.id.uuidString
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    // Stable per-presentation suffix for realtime channel names.
    private let channelScope: String

    @State private var standaloneSessionId: UUID?
    @State private var session: GameSession?
    @State private var players: [GamePlayer] = []
    @State private var turns: [GameTurn] = []
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?
    @State private var selectedTier = "normal"

    // Turn IDs whose coin animation has finished, so the prompt card
    // only appears after the coin settles.
    @State private var revealedTurnIds: Set<UUID> = []
    @State private var isFlipping = false

    // Dare proof capture
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isUploadingProof = false

    @State private var showPassConfirm = false
    @State private var showEndConfirm = false
    @State private var copiedCode = false

    private var myUserId: UUID? { auth.session?.user.id }

    private var currentTurn: GameTurn? {
        turns.last(where: { $0.isPending || $0.isPrompted })
    }

    private var finishedTurns: [GameTurn] {
        turns.filter { $0.isCompleted || $0.isPassed }
    }

    private var amPlayer: Bool {
        players.contains(where: { $0.userId == myUserId })
    }

    private var amStarter: Bool {
        session?.startedBy == myUserId
    }

    private var canEndGame: Bool {
        amStarter || (meetup != nil && meetup?.hostId == myUserId)
    }

    private var isMyTurn: Bool {
        currentTurn?.playerId == myUserId
    }

    private var currentPlayerName: String {
        guard let turn = currentTurn else { return "Player" }
        return players.first(where: { $0.userId == turn.playerId })?.displayName
            ?? turn.playerDisplayName
            ?? "Player"
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let session {
                    if session.isLobby {
                        lobbyView(session)
                    } else if session.isActive {
                        activeGameView(session)
                    } else {
                        scoreboardView(title: "Game over")
                    }
                } else {
                    setupView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationTitle("Truth or Dare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let session, !session.isEnded, canEndGame {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("End", role: .destructive) { showEndConfirm = true }
                    }
                }
            }
            .task {
                await load()
                async let sessionChanges: Void = subscribeToTable("game_sessions", channelSuffix: "sessions")
                async let playerChanges: Void = subscribeToTable("game_players", channelSuffix: "players")
                async let turnChanges: Void = subscribeToTable("game_turns", channelSuffix: "turns")
                _ = await (sessionChanges, playerChanges, turnChanges)
            }
            .confirmationDialog("End the game for everyone?", isPresented: $showEndConfirm, titleVisibility: .visible) {
                Button("End Game", role: .destructive) {
                    Task { await endGame() }
                }
                Button("Keep Playing", role: .cancel) {}
            }
            .confirmationDialog("Chicken out?", isPresented: $showPassConfirm, titleVisibility: .visible) {
                Button("Pass (everyone will know)", role: .destructive) {
                    Task { await passTurn() }
                }
                Button("Do it", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView { image in
                    Task { await submitProof(image) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibraryPicker, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task { await submitProof(from: item) }
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Setup (no live session yet)

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "flame.circle.fill")
                    .scaledFont(size: 64)
                    .foregroundStyle(Color.coral)
                Text("Truth or Dare")
                    .scaledFont(size: 28, weight: .black)
                    .foregroundStyle(.white)
                Text("The coin picks. Dares need photo proof.\nChickening out goes on the scoreboard.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Text("Pick the vibe")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color(white: 0.6))
                HStack(spacing: 10) {
                    tierCard(
                        tier: "normal",
                        title: "Normal",
                        subtitle: "Safe for brunch",
                        symbol: "face.smiling.inverse"
                    )
                    tierCard(
                        tier: "spicy",
                        title: "Spicy",
                        subtitle: "No survivors",
                        symbol: "flame.fill"
                    )
                }
            }
            .padding(.horizontal, 20)

            Button {
                Task { await startSession() }
            } label: {
                Label("Start Game", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isActing)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("btn_start_game")

            Spacer()
        }
    }

    private func tierCard(tier: String, title: String, subtitle: String, symbol: String) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            selectedTier = tier
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .scaledFont(size: 26)
                    .foregroundStyle(isSelected ? Color.coral : Color(white: 0.5))
                Text(title)
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .scaledFont(size: 11)
                    .foregroundStyle(Color(white: 0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.coral : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lobby

    private func lobbyView(_ session: GameSession) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Waiting for the squad")
                    .scaledFont(size: 24, weight: .black)
                    .foregroundStyle(.white)
                tierChip(session)
            }
            .padding(.top, 24)

            if let code = session.inviteCode {
                inviteCodeChip(code)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(players) { player in
                        HStack(spacing: 12) {
                            ProfileAvatarView(
                                displayName: player.displayName,
                                avatarUrl: player.avatarUrl,
                                userId: player.userId,
                                size: 38
                            )
                            Text(player.displayName ?? "Player")
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(.white)
                            if player.userId == session.startedBy {
                                Text("HOST")
                                    .scaledFont(size: 9, weight: .black)
                                    .foregroundStyle(Color.coral)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.coral.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusLive)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                if !amPlayer {
                    Button {
                        Task { await joinSession() }
                    } label: {
                        Label("Join Game", systemImage: "person.fill.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isActing)
                    .accessibilityIdentifier("btn_join_game")
                } else if amStarter {
                    Button {
                        Task { await beginGame() }
                    } label: {
                        Label(
                            players.count >= 2 ? "Everyone's in — Start" : "Need at least 2 players",
                            systemImage: "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isActing || players.count < 2)
                    .accessibilityIdentifier("btn_begin_game")
                } else {
                    Text("Waiting for \(starterName) to start the game…")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    /// Copyable invite-code chip so the host can read the code out or
    /// paste it into any chat.
    private func inviteCodeChip(_ code: String) -> some View {
        Button {
            UIPasteboard.general.string = code
            copiedCode = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copiedCode = false
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share code")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Color(white: 0.55))
                    Text(code)
                        .scaledFont(size: 24, weight: .black)
                        .foregroundStyle(Color.coral)
                        .tracking(6)
                }
                Image(systemName: copiedCode ? "checkmark.circle.fill" : "doc.on.doc")
                    .scaledFont(size: 16)
                    .foregroundStyle(copiedCode ? Color.statusLive : Color(white: 0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chip_invite_code")
        .accessibilityLabel("Share code \(code). Tap to copy.")
    }

    private var starterName: String {
        guard let session else { return "the host" }
        return players.first(where: { $0.userId == session.startedBy })?.displayName ?? "the host"
    }

    // MARK: - Active game

    private func activeGameView(_ session: GameSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                tierChip(session)
                Spacer()
                if let turn = currentTurn {
                    Text("Round \(turn.turnNumber)")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(Color(white: 0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // The stage: coin flip until the coin settles, then the prompt.
            Group {
                if let turn = currentTurn {
                    if turn.isPending || !revealedTurnIds.contains(turn.id) {
                        CoinFlipView(
                            isMyTurn: isMyTurn,
                            playerName: currentPlayerName,
                            result: turn.coinResult,
                            isFlipping: isFlipping,
                            onFlip: { Task { await flipCoin() } },
                            onLanded: { revealedTurnIds.insert(turn.id) }
                        )
                        .id(turn.id)
                    } else {
                        promptStage(turn)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !amPlayer {
                Button {
                    Task { await joinSession() }
                } label: {
                    Label("Jump in next round", systemImage: "person.fill.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(isActing)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            if !finishedTurns.isEmpty {
                gameFeed
            }
        }
    }

    private func tierChip(_ session: GameSession) -> some View {
        Label(
            session.isSpicy ? "Spicy" : "Normal",
            systemImage: session.isSpicy ? "flame.fill" : "face.smiling.inverse"
        )
        .scaledFont(size: 11, weight: .bold)
        .foregroundStyle(session.isSpicy ? Color(red: 0.95, green: 0.45, blue: 0.25) : Color.coral)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.appSurface)
        .clipShape(Capsule())
    }

    // MARK: - Prompt stage (coin has landed)

    private func promptStage(_ turn: GameTurn) -> some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 14) {
                Label(
                    turn.isDare ? "TAILS — DARE" : "HEADS — TRUTH",
                    systemImage: turn.isDare ? "flame.fill" : "quote.bubble.fill"
                )
                .scaledFont(size: 13, weight: .black)
                .foregroundStyle(turn.isDare ? Color(red: 0.95, green: 0.45, blue: 0.25) : Color.coral)
                .tracking(2)

                Text(turn.promptText ?? "")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Text(isMyTurn ? promptInstruction(turn) : "\(currentPlayerName) is on the clock…")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color(white: 0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 16)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        (turn.isDare ? Color(red: 0.95, green: 0.45, blue: 0.25) : Color.coral).opacity(0.35),
                        lineWidth: 1.5
                    )
            )
            .padding(.horizontal, 20)

            if isMyTurn {
                VStack(spacing: 10) {
                    if turn.isDare {
                        Button {
                            captureProof()
                        } label: {
                            if isUploadingProof {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Post Photo Proof", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isActing || isUploadingProof)
                        .accessibilityIdentifier("btn_post_proof")
                    } else {
                        Button {
                            Task { await completeTruth() }
                        } label: {
                            Label("Answered", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isActing)
                        .accessibilityIdentifier("btn_truth_answered")
                    }

                    Button {
                        showPassConfirm = true
                    } label: {
                        Label("Chicken out", systemImage: "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(isActing || isUploadingProof)
                    .accessibilityIdentifier("btn_pass_turn")
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    private func promptInstruction(_ turn: GameTurn) -> String {
        turn.isDare
            ? "Do it and post a photo of yourself — or chicken out."
            : "Answer out loud, then tap Answered."
    }

    // MARK: - Game feed

    private var gameFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game feed")
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(Color(white: 0.55))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(finishedTurns.reversed()) { turn in
                        feedCard(turn)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 10)
        .background(Color.appSurface.opacity(0.6))
    }

    private func feedCard(_ turn: GameTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if turn.isDare, turn.isCompleted, let urlString = turn.proofPhotoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        feedPlaceholder(symbol: "photo")
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                feedPlaceholder(symbol: turn.isPassed ? "bird.fill" : "quote.bubble.fill")
                    .frame(width: 110, height: 110)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 4) {
                Text(playerName(for: turn))
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if turn.isPassed {
                    Text("🐔")
                        .scaledFont(size: 10)
                } else {
                    Image(systemName: turn.isDare ? "flame.fill" : "checkmark.circle.fill")
                        .scaledFont(size: 9)
                        .foregroundStyle(turn.isDare ? Color(red: 0.95, green: 0.45, blue: 0.25) : Color.statusLive)
                }
            }
            .frame(width: 110)
        }
    }

    private func feedPlaceholder(symbol: String) -> some View {
        Image(systemName: symbol)
            .scaledFont(size: 28)
            .foregroundStyle(Color(white: 0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playerName(for turn: GameTurn) -> String {
        players.first(where: { $0.userId == turn.playerId })?.displayName
            ?? turn.playerDisplayName
            ?? "Player"
    }

    // MARK: - Scoreboard

    private func scoreboardView(title: String) -> some View {
        let entries = GameScoreboard.compute(players: players, turns: turns)
        return VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("🏆")
                    .scaledFont(size: 48)
                Text(title)
                    .scaledFont(size: 26, weight: .black)
                    .foregroundStyle(.white)
                Text("Passes don't lie.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.top, 24)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        HStack(spacing: 12) {
                            Text(rankBadge(idx, entry: entry))
                                .scaledFont(size: 18)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .scaledFont(size: 15, weight: .semibold)
                                    .foregroundStyle(.white)
                                Text("\(entry.completedTruths) truths · \(entry.completedDares) dares")
                                    .scaledFont(size: 11)
                                    .foregroundStyle(Color(white: 0.55))
                            }
                            Spacer()
                            if entry.passes > 0 {
                                Text("🐔 \(entry.passes)")
                                    .scaledFont(size: 13, weight: .bold)
                                    .foregroundStyle(Color.statusLate)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        if idx < entries.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)

                if !finishedTurns.isEmpty {
                    gameFeed
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func rankBadge(_ index: Int, entry: GameScoreEntry) -> String {
        switch index {
        case 0:  return "🥇"
        case 1:  return "🥈"
        case 2:  return "🥉"
        default: return "\(index + 1)."
        }
    }

    // MARK: - Data

    private func load(showErrors: Bool = false) async {
        do {
            if let meetup {
                if let live = try await TruthOrDareService.shared.fetchLiveSession(meetupId: meetup.id) {
                    session = live
                } else if let current = session {
                    // No live session — the open one may have just ended.
                    session = try await TruthOrDareService.shared.fetchSession(sessionId: current.id) ?? current
                } else {
                    session = nil
                }
            } else if let sessionId = session?.id ?? standaloneSessionId {
                session = try await TruthOrDareService.shared.fetchSession(sessionId: sessionId) ?? session
            }

            if let session {
                players = try await TruthOrDareService.shared.fetchPlayers(sessionId: session.id)
                turns = try await TruthOrDareService.shared.fetchTurns(sessionId: session.id)
            }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            hasLoaded = true
            if showErrors {
                self.error = error.localizedDescription
            }
        }
    }

    private func subscribeToTable(_ table: String, channelSuffix: String) async {
        let channel = SupabaseManager.shared.client.realtimeV2
            .channel("truth-or-dare-\(channelSuffix)-\(channelScope)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table)
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await load()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }

    // MARK: - Actions

    private func startSession() async {
        isActing = true
        defer { isActing = false }
        do {
            let result: StartGameResult
            if let meetup {
                result = try await TruthOrDareService.shared.startSession(meetupId: meetup.id, tier: selectedTier)
            } else {
                result = try await TruthOrDareService.shared.startSession(tier: selectedTier)
            }
            standaloneSessionId = result.sessionId
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func joinSession() async {
        guard let session else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await TruthOrDareService.shared.joinSession(sessionId: session.id)
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func beginGame() async {
        guard let session else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await TruthOrDareService.shared.beginGame(sessionId: session.id)
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func flipCoin() async {
        guard let turn = currentTurn, turn.isPending, isMyTurn, !isFlipping else { return }
        isFlipping = true
        defer { isFlipping = false }
        do {
            let result = try await TruthOrDareService.shared.flipCoin(turnId: turn.id)
            // Splice the result in locally so the animation starts
            // immediately; the Realtime echo confirms the same state.
            if let idx = turns.firstIndex(where: { $0.id == turn.id }) {
                turns[idx] = turns[idx].applyingFlip(result)
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func completeTruth() async {
        guard let turn = currentTurn, turn.isPrompted, isMyTurn else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await TruthOrDareService.shared.completeTurn(turnId: turn.id, proofPath: nil)
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func passTurn() async {
        guard let turn = currentTurn, turn.isPrompted, isMyTurn else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await TruthOrDareService.shared.passTurn(turnId: turn.id)
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func endGame() async {
        guard let session else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await TruthOrDareService.shared.endSession(sessionId: session.id)
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Dare proof

    private func captureProof() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            // Simulator / devices without a camera.
            showLibraryPicker = true
        }
    }

    private func submitProof(_ image: UIImage) async {
        guard let turn = currentTurn, turn.isPrompted, isMyTurn else { return }
        isUploadingProof = true
        defer { isUploadingProof = false }
        guard let session else { return }
        do {
            let path = try await TruthOrDareService.shared.uploadProofPhoto(
                image: image,
                sessionId: session.id,
                meetupId: meetup?.id
            )
            try await TruthOrDareService.shared.completeTurn(turnId: turn.id, proofPath: path)
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func submitProof(from item: PhotosPickerItem) async {
        defer { libraryItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await submitProof(image)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
