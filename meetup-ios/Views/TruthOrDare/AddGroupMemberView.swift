import SwiftUI

/// Friend picker for adding members to a game group. Only accepted
/// friends of the owner are listed (the server enforces the same
/// gate); friends who are already members are shown grayed out.
struct AddGroupMemberView: View {
    @Environment(\.dismiss) private var dismiss

    let groupId: UUID
    /// User ids already in the group, kept locally in sync as adds
    /// succeed so rows gray out immediately.
    @State var memberIds: Set<UUID>

    @State private var friends: [Profile] = []
    @State private var searchText = ""
    @State private var hasLoaded = false
    @State private var addingIds: Set<UUID> = []
    @State private var error: String?

    private var filteredFriends: [Profile] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return friends }
        return friends.filter {
            ($0.displayName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasLoaded && friends.isEmpty {
                    emptyState
                } else {
                    friendList
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search friends")
            .task { await loadFriends() }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No friends yet",
            systemImage: "person.2.slash",
            description: Text("Add friends from the People tab first — only friends can join your group.")
        )
    }

    private var friendList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filteredFriends.enumerated()), id: \.element.id) { idx, friend in
                    friendRow(friend)
                    if idx < filteredFriends.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(16)
        }
    }

    private func friendRow(_ friend: Profile) -> some View {
        let isMember = memberIds.contains(friend.id)
        let isAdding = addingIds.contains(friend.id)

        return Button {
            Task { await add(friend) }
        } label: {
            HStack(spacing: 12) {
                ProfileAvatarView(profile: friend, size: 36)

                Text(friend.displayName ?? "Friend")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(isMember ? DS.Color.textSecondary : DS.Color.textPrimary)

                Spacer()

                if isAdding {
                    ProgressView()
                } else if isMember {
                    Text("Member")
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .scaledFont(size: 20)
                        .foregroundStyle(Color.coral)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMember || isAdding)
    }

    // MARK: - Data

    private func loadFriends() async {
        do {
            friends = try await GameGroupService.shared.fetchFriends()
                .sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add(_ friend: Profile) async {
        addingIds.insert(friend.id)
        defer { addingIds.remove(friend.id) }
        do {
            try await GameGroupService.shared.addMember(groupId: groupId, userId: friend.id)
            memberIds.insert(friend.id)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
