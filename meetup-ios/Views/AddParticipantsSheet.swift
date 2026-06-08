import SwiftUI

struct AddParticipantsSheet: View {
    let meetupId: UUID
    let existingParticipantIds: Set<UUID>
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Profile] = []
    @State private var inviteePhone = ""
    @State private var foundUser: FoundUser?
    @State private var isSearchingUser = false
    @State private var isAdding = false
    @State private var error: String?
    @State private var addedNames: [String] = []

    private var phoneDigits: String {
        let raw = inviteePhone.hasPrefix("+1") ? String(inviteePhone.dropFirst(2)) : inviteePhone
        return raw.filter(\.isNumber)
    }

    private var availableFriends: [Profile] {
        friends.filter { !existingParticipantIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !availableFriends.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(availableFriends) { friend in
                                    AddFriendChip(friend: friend) {
                                        Task { await addUser(id: friend.id, name: friend.displayName ?? "Unknown") }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.appSurface)
                    } header: {
                        Text("FROM YOUR SQUAD")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.4))
                            .textCase(nil)
                    }
                }

                Section {
                    HStack {
                        TextField("+1 (646) 946-6861", text: $inviteePhone)
                            .keyboardType(.phonePad)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .tint(Color.coral)
                        if isSearchingUser || isAdding {
                            ProgressView()
                        } else {
                            Button("Search") { Task { await searchUser() } }
                                .disabled(phoneDigits.count < 10)
                                .foregroundStyle(Color.coral)
                        }
                    }
                    .listRowBackground(Color.appSurface)

                    if let user = foundUser {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text(user.phone)
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.6))
                            }
                            Spacer()
                            Button("Add") { Task { await addUser(id: user.id, name: user.displayName) } }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.coral)
                                .controlSize(.small)
                                .disabled(isAdding)
                        }
                        .listRowBackground(Color.appSurface)
                    }
                } header: {
                    Text("SEARCH BY PHONE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                if !addedNames.isEmpty {
                    Section {
                        ForEach(addedNames, id: \.self) { name in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.statusLive)
                                Text(name)
                                    .foregroundStyle(.white)
                            }
                            .listRowBackground(Color.appSurface)
                        }
                    } header: {
                        Text("ADDED THIS SESSION")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.4))
                            .textCase(nil)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                friends = (try? await MeetupService.shared.getFriends()) ?? []
            }
        }
    }

    private func searchUser() async {
        let digits = phoneDigits
        guard digits.count == 10 else { return }
        let e164 = "+1" + digits
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        isSearchingUser = true
        foundUser = nil
        error = nil
        do {
            if let user = try await MeetupService.shared.findUserByPhone(e164) {
                if user.id == myId {
                    error = "That's you!"
                } else if existingParticipantIds.contains(user.id) || addedNames.contains(user.displayName) {
                    error = "\(user.displayName) is already in this meetup"
                } else {
                    foundUser = user
                }
            } else {
                error = "No user found with that number"
            }
        } catch {
            self.error = error.localizedDescription
        }
        isSearchingUser = false
    }

    private func addUser(id: UUID, name: String) async {
        isAdding = true
        error = nil
        do {
            try await MeetupService.shared.inviteParticipant(meetupId: meetupId, userId: id)
            addedNames.append(name)
            foundUser = nil
            inviteePhone = ""
            onAdded()
        } catch {
            self.error = error.localizedDescription
        }
        isAdding = false
    }
}

// MARK: - Add Friend Chip

private struct AddFriendChip: View {
    let friend: Profile
    let onTap: () -> Void

    private var initial: String {
        String((friend.displayName ?? "?").prefix(1)).uppercased()
    }

    private var shortName: String {
        let name = friend.displayName ?? "Unknown"
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return String(first.prefix(9))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Circle()
                    .fill(Color.coral.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(initial)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.coral)
                    }
                Text(shortName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(1)
            }
            .frame(width: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(shortName) to meetup")
    }
}
