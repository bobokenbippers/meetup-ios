import SwiftUI
import PhotosUI
import Supabase
import UIKit

/// Truth or Dare game screen. Handles the whole session lifecycle:
/// setup (tier pick), lobby, live game (coin flip → prompt →
/// proof/answer/pass), and the end-of-game scoreboard. All game
/// state is server-authoritative and synced over Supabase Realtime.
///
/// Runs in two modes: standalone (the default) or embedded in a
/// meetup, where any meetup participant can play.
struct TruthOrDareView: View {
    let meetup: Meetup?

    /// Game group to stamp a newly started session with. Only set in
    /// standalone mode when starting from a group's detail screen.
    let groupId: UUID?

    /// Standalone mode: open an existing session directly, or start
    /// from the tier-pick setup screen when nil. Pass `groupId` when
    /// starting on behalf of a game group.
    init(sessionId: UUID? = nil, groupId: UUID? = nil) {
        self.meetup = nil
        self.groupId = groupId
        self._standaloneSessionId = State(initialValue: sessionId)
        self.channelScope = sessionId?.uuidString ?? UUID().uuidString
    }

    /// Meetup-embedded mode: shows the meetup's live game, if any.
    init(meetup: Meetup) {
        self.meetup = meetup
        self.groupId = nil
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
    @State private var votes: [GameTurnVote] = []
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?
    @State private var selectedTier = "normal"
    @State private var selectedMode = "turn_based"

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

    // Custom dare assignment
    @State private var customDareText: String = ""
    @State private var showCustomDareInput = false
    @State private var isAssigningDare = false

    private var myUserId: UUID? { auth.session?.user.id }

    private var currentTurn: GameTurn? {
        turns.last(where: { $0.isPending || $0.isPrompted || $0.isVoting })
    }

    private var finishedTurns: [GameTurn] {
        turns.filter { $0.isCompleted || $0.isPassed || $0.isFailed }
    }

    private var amPlayer: Bool {
        players.contains(where: { $0.userId == myUserId })
    }

    private var amStarter: Bool {
        session?.startedBy == myUserId
    }

    // Any player can end a game (a soft-locked game shouldn't trap the
    // people in it just because they didn't start it). Meetup hosts can
    // end a meetup-embedded game even if they never joined.
    private var canEndGame: Bool {
        amPlayer || (meetup != nil && meetup?.hostId == myUserId)
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
                async let voteChanges: Void = subscribeToTable("game_turn_votes", channelSuffix: "votes")
                _ = await (sessionChanges, playerChanges, turnChanges, voteChanges)
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
            .onChange(of: currentTurn?.id) { _, _ in
                customDareText = ""
                showCustomDareInput = false
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }

        }
        .tint(Color.coral)
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
                    .foregroundStyle(DS.Color.textPrimary)
                Text("The coin picks. Dares need photo proof.\nChickening out goes on the scoreboard.")
                    .scaledFont(size: 13)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Text("Pick a mode")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(DS.Color.textSecondary)
                HStack(spacing: 10) {
                    modeCard(
                        mode: "turn_based",
                        title: "Turn-Based",
                        subtitle: "Take turns in order",
                        symbol: "person.crop.circle.badge.clock"
                    )
                    modeCard(
                        mode: "free_for_all",
                        title: "Free-for-All",
                        subtitle: "Anyone grabs a card",
                        symbol: "bolt.fill"
                    )
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Text("Pick the vibe")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(DS.Color.textSecondary)
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
                    .foregroundStyle(isSelected ? tierAccent(for: tier) : Color(white: 0.5))
                Text(title)
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle)
                    .scaledFont(size: 11)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? tierAccent(for: tier) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
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
                    .foregroundStyle(DS.Color.textPrimary)
                tierChip(session)
            }
            .padding(.top, 24)

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
                                .foregroundStyle(DS.Color.textPrimary)
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
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
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
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // The stage: coin flip until the coin settles, then the prompt.
            Group {
                if let turn = currentTurn {
                    if turn.isVoting {
                        verdictStage(turn)
                    } else if turn.isPending || !revealedTurnIds.contains(turn.id) {
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
                    // Active session with no playable turn = the game
                    // stalled. Don't spin forever — give players a way out.
                    stalledStage
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

    /// Shown when an active game has no playable turn — it soft-locked.
    /// Replaces the old infinite spinner so players aren't trapped.
    private var stalledStage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(size: 44)
                .foregroundStyle(Color.statusLate)
            Text("This game stalled")
                .scaledFont(size: 20, weight: .black)
                .foregroundStyle(DS.Color.textPrimary)
            Text(canEndGame
                 ? "The round didn't advance. End the game to clear it for everyone."
                 : "The round didn't advance. Ask a player to end it, or close this screen.")
                .scaledFont(size: 13)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                if canEndGame {
                    Button {
                        showEndConfirm = true
                    } label: {
                        Label("End Game", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isActing)
                    .accessibilityIdentifier("btn_end_stalled_game")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tierChip(_ session: GameSession) -> some View {
        Label(
            session.isSpicy ? "Spicy" : "Normal",
            systemImage: session.isSpicy ? "flame.fill" : "face.smiling.inverse"
        )
        .scaledFont(size: 11, weight: .bold)
        .foregroundStyle(tierAccent(for: session.tier))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.appSurface)
        .clipShape(Capsule())
    }

    private func tierAccent(for tier: String) -> Color {
        tier == "spicy" ? Color.appSecondaryAccent : Color.coral
    }

    private func modeCard(mode: String, title: String, subtitle: String, symbol: String) -> some View {
        let isSelected = selectedMode == mode
        let accent = Color.purple
        return Button {
            selectedMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .scaledFont(size: 26)
                    .foregroundStyle(isSelected ? accent : Color(white: 0.5))
                Text(title)
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle)
                    .scaledFont(size: 11)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? accent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Verdict vote

    private func verdictStage(_ turn: GameTurn) -> some View {
        let turnVotes = votesForTurn(turn)
        let yesCount = turnVotes.filter { $0.vote }.count
        let noCount = turnVotes.filter { !$0.vote }.count
        let eligibleCount = max(players.count - 1, 0)
        let myVote = myUserId.flatMap { userId in turnVotes.first(where: { $0.voterId == userId })?.vote }
        let canVote = amPlayer && !isMyTurn

        return VStack(spacing: 20) {
            Spacer()

            promptCard(turn)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                Label("Squad verdict", systemImage: "checkmark.seal.fill")
                    .scaledFont(size: 13, weight: .black)
                    .foregroundStyle(Color.appSecondaryAccent)

                Text(verdictMessage(for: turn, yesCount: yesCount, noCount: noCount, eligibleCount: eligibleCount))
                    .scaledFont(size: 13)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    verdictVoteButton(
                        title: "Counts",
                        systemImage: "hand.thumbsup.fill",
                        count: yesCount,
                        isSelected: myVote == true,
                        isDisabled: !canVote || isActing,
                        action: { Task { await voteOnTurn(turn, counts: true) } }
                    )
                    verdictVoteButton(
                        title: "Doesn't",
                        systemImage: "hand.thumbsdown.fill",
                        count: noCount,
                        isSelected: myVote == false,
                        isDisabled: !canVote || isActing,
                        action: { Task { await voteOnTurn(turn, counts: false) } }
                    )
                }

                if !canVote {
                    Text(isMyTurn ? "You did the turn. Let the squad judge this one." : "Players are voting.")
                        .scaledFont(size: 12)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func verdictVoteButton(
        title: String,
        systemImage: String,
        count: Int,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .scaledFont(size: 12, weight: .bold)
                Text(title)
                    .scaledFont(size: 13, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count)")
                    .scaledFont(size: 13, weight: .black)
            }
            .foregroundStyle(isSelected ? Color.white : DS.Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isSelected ? Color.appSecondaryAccent : Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isSelected ? 0.55 : 1)
    }

    private func verdictMessage(for turn: GameTurn, yesCount: Int, noCount: Int, eligibleCount: Int) -> String {
        let noun = turn.isDare ? "dare" : "truth"
        if eligibleCount <= 0 {
            return "No one else can vote on this \(noun), so it is waiting for another player."
        }
        let remaining = max(eligibleCount - yesCount - noCount, 0)
        if remaining == 0 {
            return "All votes are in. The server will settle the next turn."
        }
        return "\(yesCount) count it, \(noCount) don't. \(remaining) vote\(remaining == 1 ? "" : "s") left."
    }

    private func votesForTurn(_ turn: GameTurn) -> [GameTurnVote] {
        votes.filter { $0.turnId == turn.id }
    }

    // MARK: - Prompt stage (coin has landed)

    private func promptStage(_ turn: GameTurn) -> some View {
        VStack(spacing: 20) {
            Spacer()

            promptCard(turn)
                .padding(.horizontal, 20)

            // Action area depends on role and dare assignment state.
            if turn.isDare && !turn.dareLocked {
                // Assigning phase: the doer waits; other players assign the dare.
                if amPlayer && !isMyTurn {
                    dareAssignmentActions(turn)
                        .padding(.horizontal, 20)
                } else if isMyTurn {
                    dareWaitingIndicator
                        .padding(.horizontal, 20)
                }
            } else if isMyTurn {
                // Dare is locked (or it's a truth): doer acts.
                dareOrTruthActions(turn)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    /// The card showing the prompt kind label + text + subtitle.
    private func promptCard(_ turn: GameTurn) -> some View {
        let accentColor = turn.isDare
            ? Color.appSecondaryAccent
            : Color.coral
        return VStack(spacing: 14) {
            Label(
                turn.isDare ? "TAILS — DARE" : "HEADS — TRUTH",
                systemImage: turn.isDare ? "flame.fill" : "quote.bubble.fill"
            )
            .scaledFont(size: 13, weight: .black)
            .foregroundStyle(accentColor)
            .tracking(2)

            Text(turn.promptText ?? "")
                .scaledFont(size: 22, weight: .bold)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Text(promptCardSubtitle(turn))
                .scaledFont(size: 12)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accentColor.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func promptCardSubtitle(_ turn: GameTurn) -> String {
        if turn.isDare && !turn.dareLocked {
            if isMyTurn {
                return "Waiting for your dare to be set…"
            } else if amPlayer {
                return "Keep or customize this dare for \(currentPlayerName)."
            } else {
                return "Waiting for a dare to be set for \(currentPlayerName)…"
            }
        }
        if isMyTurn {
            return turn.isDare
                ? "Do it and post a photo of yourself — or chicken out."
                : "Answer out loud, then tap Answered."
        }
        return "\(currentPlayerName) is on the clock…"
    }

    /// Shown to the doer while the assigner is picking the dare.
    private var dareWaitingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(white: 0.55))
            Text("Waiting for someone to set your dare…")
                .scaledFont(size: 13)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    /// Shown to the assigner(s) — let them keep or replace the suggested dare.
    private func dareAssignmentActions(_ turn: GameTurn) -> some View {
        VStack(spacing: 12) {
            // Keep the suggestion
            Button {
                Task { await assignDare(turn: turn, text: turn.promptText ?? "") }
            } label: {
                Label("Keep this dare", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isAssigningDare)
            .accessibilityIdentifier("btn_keep_dare")

            // Toggle custom input
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCustomDareInput.toggle()
                    if !showCustomDareInput { customDareText = "" }
                }
            } label: {
                Label(
                    showCustomDareInput ? "Cancel custom dare" : "Set a custom dare",
                    systemImage: showCustomDareInput ? "xmark.circle" : "pencil"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(isAssigningDare)
            .accessibilityIdentifier("btn_toggle_custom_dare")

            if showCustomDareInput {
                VStack(spacing: 8) {
                    TextField("Type a dare…", text: $customDareText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .scaledFont(size: 15)
                        .foregroundStyle(DS.Color.textPrimary)
                        .tint(Color.appSecondaryAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.appSecondaryAccent.opacity(0.4), lineWidth: 1)
                        )
                        .accessibilityIdentifier("field_custom_dare")

                    Button {
                        Task { await assignDare(turn: turn, text: customDareText) }
                    } label: {
                        if isAssigningDare {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Assign this dare", systemImage: "flame.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isAssigningDare || customDareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("btn_assign_custom_dare")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Standard action buttons for the doer once the dare is locked (or for truths).
    private func dareOrTruthActions(_ turn: GameTurn) -> some View {
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
    }

    // MARK: - Game feed

    private var gameFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game feed")
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(DS.Color.textSecondary)
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
                feedPlaceholder(symbol: feedSymbol(for: turn))
                    .frame(width: 110, height: 110)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 4) {
                Text(playerName(for: turn))
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if turn.isPassed {
                    Text("🐔")
                        .scaledFont(size: 10)
                } else if turn.isFailed {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(size: 9)
                        .foregroundStyle(Color.statusLate)
                } else {
                    Image(systemName: turn.isDare ? "flame.fill" : "checkmark.circle.fill")
                        .scaledFont(size: 9)
                        .foregroundStyle(turn.isDare ? Color.appSecondaryAccent : Color.coral)
                }
            }
            .frame(width: 110)
        }
    }

    private func feedSymbol(for turn: GameTurn) -> String {
        if turn.isPassed { return "bird.fill" }
        if turn.isFailed { return "xmark.circle.fill" }
        return "quote.bubble.fill"
    }

    private func feedPlaceholder(symbol: String) -> some View {
        Image(systemName: symbol)
            .scaledFont(size: 28)
            .foregroundStyle(DS.Color.textSecondary)
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
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Passes don't lie.")
                    .scaledFont(size: 13)
                    .foregroundStyle(DS.Color.textSecondary)
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
                                    .foregroundStyle(DS.Color.textPrimary)
                                Text("\(entry.completedTruths) truths · \(entry.completedDares) dares")
                                    .scaledFont(size: 11)
                                    .foregroundStyle(DS.Color.textSecondary)
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
                votes = try await TruthOrDareService.shared.fetchVotes(turnIds: turns.map(\.id))
            } else {
                players = []
                turns = []
                votes = []
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
                // TODO: pass selectedMode to start_truth_or_dare when backend supports it
                result = try await TruthOrDareService.shared.startSession(meetupId: meetup.id, tier: selectedTier)
            } else {
                // TODO: pass selectedMode to start_truth_or_dare when backend supports it
                result = try await TruthOrDareService.shared.startSession(tier: selectedTier, groupId: groupId)
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

    private func voteOnTurn(_ turn: GameTurn, counts: Bool) async {
        guard turn.isVoting, amPlayer, !isMyTurn else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await TruthOrDareService.shared.voteTurn(turnId: turn.id, vote: counts)
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

    private func assignDare(turn: GameTurn, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAssigningDare = true
        defer { isAssigningDare = false }
        do {
            try await TruthOrDareService.shared.assignDare(turnId: turn.id, promptText: trimmed)
            showCustomDareInput = false
            customDareText = ""
            await load(showErrors: true)
        } catch is CancellationError {
            return
        } catch {
            // Silently ignore "already locked" races; surface other errors.
            let msg = error.localizedDescription
            if !msg.contains("already assigned") {
                self.error = msg
            }
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
