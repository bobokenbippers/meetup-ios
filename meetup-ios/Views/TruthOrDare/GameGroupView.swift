import SwiftUI
import Auth

/// Game group detail: the member roster, owner management (add /
/// remove members, delete group), leave for non-owners, and the
/// entry point for starting a group game.
struct GameGroupView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let group: GameGroup
    /// Called after the group is deleted or left, so the list screen
    /// can refresh.
    var onChanged: (() -> Void)?

    @State private var members: [GameGroupMember] = []
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?

    @State private var showAddMember = false
    @State private var showStartGame = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    private var myUserId: UUID? { auth.session?.user.id }
    private var amOwner: Bool { group.ownerId == myUserId }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                startGameButton
                membersSection
                if amOwner {
                    deleteButton
                } else {
                    leaveButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadMembers() }
        .task { await loadMembers() }
        .sheet(isPresented: $showAddMember, onDismiss: { Task { await loadMembers() } }) {
            AddGroupMemberView(groupId: group.id, memberIds: Set(members.map(\.userId)))
        }
        .fullScreenCover(isPresented: $showStartGame) {
            TruthOrDareView(groupId: group.id)
                .environment(auth)
        }
        .confirmationDialog("Leave \(group.name)?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive) {
                Task { await leaveGroup() }
            }
        } message: {
            Text("The owner can add you back later.")
        }
        .confirmationDialog("Delete \(group.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) {
                Task { await deleteGroup() }
            }
        } message: {
            Text("This removes the group for every member. Past games are kept.")
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .scaledFont(size: 40)
                .foregroundStyle(Color.coral)
            Text(group.name)
                .scaledFont(size: 22, weight: .black)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                .scaledFont(size: 12)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Start game

    private var startGameButton: some View {
        Button {
            showStartGame = true
        } label: {
            Label("Start Game", systemImage: "play.fill")
                .scaledFont(size: 16, weight: .bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.coral)
        .accessibilityIdentifier("btn_start_group_game")
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Members")
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
                if amOwner {
                    Button {
                        showAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                            .scaledFont(size: 13, weight: .semibold)
                    }
                    .tint(Color.coral)
                    .accessibilityIdentifier("btn_add_group_member")
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { idx, member in
                    memberRow(member)
                    if idx < members.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func memberRow(_ member: GameGroupMember) -> some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                displayName: member.displayName,
                avatarUrl: member.avatarUrl,
                userId: member.userId,
                size: 36
            )

            HStack(spacing: 6) {
                Text(member.userId == myUserId ? "You" : (member.displayName ?? "Player"))
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(DS.Color.textPrimary)
                if member.userId == group.ownerId {
                    Image(systemName: "crown.fill")
                        .scaledFont(size: 11)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Group owner")
                }
            }

            Spacer()

            if amOwner && member.userId != group.ownerId {
                Button {
                    Task { await removeMember(member) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .scaledFont(size: 18)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .disabled(isActing)
                .accessibilityLabel("Remove \(member.displayName ?? "member")")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Leave / delete

    private var leaveButton: some View {
        Button(role: .destructive) {
            showLeaveConfirm = true
        } label: {
            Text("Leave Group")
                .scaledFont(size: 15, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(isActing)
        .accessibilityIdentifier("btn_leave_group")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("Delete Group")
                .scaledFont(size: 15, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(isActing)
        .accessibilityIdentifier("btn_delete_group")
    }

    // MARK: - Data

    private func loadMembers() async {
        do {
            members = try await GameGroupService.shared.fetchMembers(groupId: group.id)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            if !hasLoaded { self.error = error.localizedDescription }
        }
    }

    private func removeMember(_ member: GameGroupMember) async {
        isActing = true
        defer { isActing = false }
        do {
            try await GameGroupService.shared.removeMember(groupId: group.id, userId: member.userId)
            members.removeAll { $0.userId == member.userId }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func leaveGroup() async {
        isActing = true
        defer { isActing = false }
        do {
            try await GameGroupService.shared.leaveGroup(groupId: group.id)
            onChanged?()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteGroup() async {
        isActing = true
        defer { isActing = false }
        do {
            try await GameGroupService.shared.deleteGroup(groupId: group.id)
            onChanged?()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
