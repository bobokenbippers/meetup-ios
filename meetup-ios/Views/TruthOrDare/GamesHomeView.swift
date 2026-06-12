import SwiftUI

/// Landing screen for the Games tab. Start a standalone Truth or
/// Dare session, join a friend's game with their invite code, or
/// jump back into a recent game.
struct GamesHomeView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var myGames: [MyGameEntry] = []
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var error: String?

    @State private var showNewGame = false
    @State private var openedSession: OpenedGameSession?

    /// Identifiable wrapper so a joined/tapped session id can drive
    /// a fullScreenCover(item:).
    private struct OpenedGameSession: Identifiable {
        let id: UUID
    }

    private var recentGames: [MyGameEntry] {
        myGames.filter { $0.session != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    joinSection
                    if !recentGames.isEmpty {
                        recentGamesSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.appBackground)
            .navigationTitle("Games")
            .refreshable { await loadGames() }
            .task { await loadGames() }
            .fullScreenCover(isPresented: $showNewGame, onDismiss: { Task { await loadGames() } }) {
                TruthOrDareView()
                    .environment(auth)
            }
            .fullScreenCover(item: $openedSession, onDismiss: { Task { await loadGames() } }) { opened in
                TruthOrDareView(sessionId: opened.id)
                    .environment(auth)
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }

        }
    }

    // MARK: - Start a new game

    private var heroCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "flame.circle.fill")
                .scaledFont(size: 52)
                .foregroundStyle(Color.coral)
            VStack(spacing: 4) {
                Text("Truth or Dare")
                    .scaledFont(size: 24, weight: .black)
                    .foregroundStyle(.white)
                Text("The coin picks. Dares need photo proof.\nShare the code, no meetup required.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }
            Button {
                showNewGame = true
            } label: {
                Label("Start New Game", systemImage: "play.fill")
                    .scaledFont(size: 16, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.coral)
            .accessibilityIdentifier("btn_start_new_game")
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.coral.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Join with code

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join with Code")
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(Color(white: 0.6))

            HStack(spacing: 10) {
                TextField("ABC123", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .scaledFont(size: 18, weight: .bold)
                    .tracking(4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .accessibilityIdentifier("field_invite_code")

                Button {
                    Task { await joinByCode() }
                } label: {
                    if isJoining {
                        ProgressView()
                            .frame(width: 44)
                    } else {
                        Text("Join")
                            .scaledFont(size: 15, weight: .bold)
                            .frame(width: 44)
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isJoining || trimmedCode.isEmpty)
                .accessibilityIdentifier("btn_join_by_code")
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var trimmedCode: String {
        joinCode.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Recent games

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your games")
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(Color(white: 0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(recentGames.enumerated()), id: \.element.id) { idx, entry in
                    if let session = entry.session {
                        Button {
                            openedSession = OpenedGameSession(id: session.id)
                        } label: {
                            gameRow(session)
                        }
                        .buttonStyle(.plain)
                        if idx < recentGames.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func gameRow(_ session: GameSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.isSpicy ? "flame.fill" : "face.smiling.inverse")
                .scaledFont(size: 18)
                .foregroundStyle(session.isEnded ? Color(white: 0.4) : Color.coral)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.isSpicy ? "Spicy round" : "Normal round")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(session.createdAt, format: .dateTime.month(.abbreviated).day())
                        .scaledFont(size: 11)
                        .foregroundStyle(Color(white: 0.55))
                    if let code = session.inviteCode, !session.isEnded {
                        Text("· \(code)")
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(Color.coral.opacity(0.8))
                    }
                }
            }

            Spacer()

            statusChip(session)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func statusChip(_ session: GameSession) -> some View {
        Text(session.isLobby ? "LOBBY" : session.isActive ? "LIVE" : "ENDED")
            .scaledFont(size: 9, weight: .black)
            .foregroundStyle(session.isEnded ? Color(white: 0.5) : Color.statusLive)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((session.isEnded ? Color.white.opacity(0.06) : Color.statusLive.opacity(0.15)))
            .clipShape(Capsule())
    }

    // MARK: - Data

    private func loadGames() async {
        do {
            myGames = try await TruthOrDareService.shared.fetchMyGames()
        } catch is CancellationError {
            return
        } catch {
            // Quiet failure on the list — pull to refresh retries.
        }
    }

    private func joinByCode() async {
        guard !trimmedCode.isEmpty else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            let sessionId = try await TruthOrDareService.shared.joinSessionByCode(code: trimmedCode)
            joinCode = ""
            openedSession = OpenedGameSession(id: sessionId)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
