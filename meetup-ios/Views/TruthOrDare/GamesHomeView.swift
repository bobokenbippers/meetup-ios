import SwiftUI

/// Landing screen for the Games tab. Start a standalone Truth or
/// Dare session or jump back into a recent game.
struct GamesHomeView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var myGames: [MyGameEntry] = []
    @State private var myGroups: [GameGroup] = []
    @State private var error: String?

    @State private var showNewGame = false
    @State private var openedSession: OpenedGameSession?

    @State private var showNewGroupPrompt = false
    @State private var newGroupName = ""
    @State private var isCreatingGroup = false

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
                    groupsSection
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
            .navigationDestination(for: GameGroup.self) { group in
                GameGroupView(group: group) {
                    Task { await loadGames() }
                }
            }
            .alert("New Group", isPresented: $showNewGroupPrompt) {
                TextField("Group name", text: $newGroupName)
                Button("Create") { Task { await createGroup() } }
                Button("Cancel", role: .cancel) { newGroupName = "" }
            } message: {
                Text("Name your crew — you can add friends next.")
            }
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
                    .foregroundStyle(DS.Color.textPrimary)
                Text("The coin picks. Dares need photo proof.\nNo meetup required.")
                    .scaledFont(size: 12)
                    .foregroundStyle(DS.Color.textSecondary)
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

    // MARK: - Groups

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Groups")
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, 4)

            if !myGroups.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(myGroups.enumerated()), id: \.element.id) { idx, group in
                        NavigationLink(value: group) {
                            groupRow(group)
                        }
                        .buttonStyle(.plain)
                        if idx < myGroups.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button {
                newGroupName = ""
                showNewGroupPrompt = true
            } label: {
                if isCreatingGroup {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    Label("New Group", systemImage: "person.3.fill")
                        .scaledFont(size: 15, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .buttonStyle(.bordered)
            .tint(Color.coral)
            .disabled(isCreatingGroup)
            .accessibilityIdentifier("btn_new_group")
        }
    }

    private func groupRow(_ group: GameGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .scaledFont(size: 16)
                .foregroundStyle(Color.coral)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(DS.Color.textPrimary)
                if let count = group.memberCount {
                    Text("\(count) member\(count == 1 ? "" : "s")")
                        .scaledFont(size: 11)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Recent games

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your games")
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(DS.Color.textSecondary)
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
                    .foregroundStyle(DS.Color.textPrimary)
                Text(session.createdAt, format: .dateTime.month(.abbreviated).day())
                    .scaledFont(size: 11)
                    .foregroundStyle(DS.Color.textSecondary)
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
        do {
            myGroups = try await GameGroupService.shared.fetchMyGroups()
        } catch is CancellationError {
            return
        } catch {
            // Quiet failure on the list — pull to refresh retries.
        }
    }

    private func createGroup() async {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreatingGroup = true
        defer { isCreatingGroup = false }
        do {
            _ = try await GameGroupService.shared.createGroup(name: name)
            newGroupName = ""
            await loadGames()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

}
