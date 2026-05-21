import SwiftUI
import Supabase
import Contacts

struct PeopleListView: View {
    @State private var people: [Profile] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var phoneSearch = ""
    @State private var foundUser: FoundUser?
    @State private var isSearching = false
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []

    private var isSearchEnabled: Bool {
        let raw = phoneSearch.hasPrefix("+1") ? String(phoneSearch.dropFirst(2)) : phoneSearch
        return raw.filter { $0.isNumber }.count >= 10
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Glass search bar
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Contact suggestions
                    if !contactSuggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(contactSuggestions) { contact in
                                Button { Task { await selectContact(contact) } } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.coral.opacity(0.15))
                                            .frame(width: 38, height: 38)
                                            .overlay {
                                                Text(String(contact.displayName.prefix(1)).uppercased())
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(Color.coral)
                                            }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(contact.displayName)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(contact.phones.first ?? contact.emails.first ?? "")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    // Found user card
                    if let user = foundUser {
                        foundUserCard(user)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // People from meetups
                    if hasLoaded && !people.isEmpty {
                        sectionLabel("From Meetups")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        VStack(spacing: 8) {
                            ForEach(people) { person in
                                PersonCard(person: person) {
                                    Task { await removePerson(person) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    } else if hasLoaded && people.isEmpty && contactSuggestions.isEmpty && foundUser == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.coral.opacity(0.4))
                                .padding(.top, 48)
                            Text("No connections yet")
                                .font(.system(size: 16, weight: .bold))
                            Text("People you've had meetups with will appear here.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                    } else if !hasLoaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("People")
            .task {
                await load()
                await contactsManager.load()
                refreshSuggestions()
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField("Name or +1 (646) 946-6861", text: $phoneSearch)
                .keyboardType(.default)
                .autocorrectionDisabled()
                .onChange(of: phoneSearch) { _, v in
                    if v.contains(where: { $0.isLetter }) {
                        contactSuggestions = Array(contactsManager.search(v).prefix(5))
                    } else {
                        let raw = v.hasPrefix("+1") ? String(v.dropFirst(2)) : v
                        let digitsOnly = String(raw.filter { $0.isNumber }.prefix(10))
                        let formatted = PhoneFormatter.formatWithCountryCode(digitsOnly)
                        if phoneSearch != formatted {
                            phoneSearch = formatted
                        } else {
                            contactSuggestions = Array(contactsManager.search(digitsOnly).prefix(5))
                        }
                    }
                }

            if isSearching {
                ProgressView().controlSize(.small)
            } else if !phoneSearch.isEmpty {
                Button("Search") { Task { await searchUser() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSearchEnabled ? Color.coral : Color.secondary)
                    .disabled(!isSearchEnabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func foundUserCard(_ user: FoundUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.coral.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Text(String(user.displayName.prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.coral)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(user.phone)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Add") { addFriend(user) }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.coral)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.coral.opacity(0.3), lineWidth: 1)
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Logic

    private func refreshSuggestions() {
        guard !phoneSearch.isEmpty else { contactSuggestions = []; return }
        if phoneSearch.contains(where: { $0.isLetter }) {
            contactSuggestions = Array(contactsManager.search(phoneSearch).prefix(5))
        } else {
            let raw = phoneSearch.hasPrefix("+1") ? String(phoneSearch.dropFirst(2)) : phoneSearch
            let digits = raw.filter { $0.isNumber }
            contactSuggestions = digits.isEmpty ? [] : Array(contactsManager.search(digits).prefix(5))
        }
    }

    private func load() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            hasLoaded = true
            return
        }
        #endif
        do {
            people = try await MeetupService.shared.getPeopleFromMeetups()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func searchUser() async {
        guard let e164 = PhoneFormatter.toE164(phoneSearch) else { return }
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        isSearching = true
        foundUser = nil
        error = nil
        do {
            if let user = try await MeetupService.shared.findUserByPhone(e164) {
                if user.id == myId { error = "That's you!" }
                else { foundUser = user }
            } else {
                error = "No user found with that number"
            }
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    private func selectContact(_ contact: DeviceContact) async {
        isSearching = true
        contactSuggestions = []
        phoneSearch = ""
        foundUser = nil
        error = nil
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        var found: FoundUser?
        for phone in contact.phones {
            if let user = try? await MeetupService.shared.findUserByPhone(phone) { found = user; break }
        }
        if found == nil {
            for email in contact.emails {
                if let user = try? await MeetupService.shared.findUserByEmail(email) { found = user; break }
            }
        }
        if let user = found {
            if user.id == myId { error = "That's you!" }
            else { foundUser = user }
        } else {
            error = "\(contact.displayName) isn't on the app yet"
        }
        isSearching = false
    }

    private func removePerson(_ person: Profile) async {
        do {
            try await MeetupService.shared.removeFriend(userId: person.id)
            people.removeAll { $0.id == person.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addFriend(_ user: FoundUser) {
        Task {
            do {
                try await MeetupService.shared.addFriend(userId: user.id)
                phoneSearch = ""
                foundUser = nil
                error = "Friend request sent!"
                Task {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    error = nil
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Person Card

private struct PersonCard: View {
    let person: Profile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(personColor(for: person.id).opacity(0.7))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(String((person.displayName ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName ?? "Unknown")
                    .font(.system(size: 13, weight: .semibold))
                if let phone = person.phoneE164 {
                    Text(phone)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func personColor(for id: UUID) -> Color {
        let palette: [Color] = [
            Color(red: 0.910, green: 0.361, blue: 0.016),
            Color(red: 0.482, green: 0.361, blue: 0.749),
            Color(red: 0.118, green: 0.565, blue: 1.000),
            Color(red: 0.180, green: 0.800, blue: 0.443),
            Color(red: 0.910, green: 0.212, blue: 0.278),
            Color(red: 0.000, green: 0.780, blue: 0.941),
        ]
        return palette[abs(id.hashValue) % palette.count]
    }
}
