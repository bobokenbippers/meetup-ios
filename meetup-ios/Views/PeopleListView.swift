import SwiftUI
import Supabase
import Contacts

struct PeopleListView: View {
    @State private var people: [Profile] = []
    @State private var incomingRequests: [IncomingFriendRequest] = []
    @State private var pendingOutgoingIds: Set<UUID> = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var phoneSearch = ""
    @State private var foundUser: FoundUser?
    @State private var isSearching = false
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []
    @State private var contactNameOverrides: [UUID: String] = [:]

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

                    // Incoming friend requests
                    if !incomingRequests.isEmpty {
                        sectionLabel("Friend Requests")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        LazyVStack(spacing: 8) {
                            ForEach(incomingRequests) { request in
                                incomingRequestCard(request)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // People list (friends + outgoing pending + meetup people)
                    if hasLoaded && !people.isEmpty {
                        sectionLabel("People")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        LazyVStack(spacing: 8) {
                            ForEach(people) { person in
                                PersonCard(
                                    person: person,
                                    contactName: contactNameOverrides[person.id],
                                    isPending: pendingOutgoingIds.contains(person.id)
                                ) {
                                    Task { await removePerson(person) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    } else if hasLoaded && people.isEmpty && incomingRequests.isEmpty
                                && contactSuggestions.isEmpty && foundUser == nil {
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
                enrichWithContactNames()
                refreshSuggestions()
                await startFriendRequestRealtime()
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

    private func incomingRequestCard(_ request: IncomingFriendRequest) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.coral.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Text(String((request.requester.displayName ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.coral)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(request.requester.displayName ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                if let phone = request.requester.phoneE164 {
                    Text(phone)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Accept") {
                    Task { await acceptRequest(request) }
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.coral)
                .clipShape(Capsule())

                Button("Decline") {
                    Task { await declineRequest(request) }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.coral.opacity(0.4), lineWidth: 1)
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Logic

    private func isPlaceholderName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.isEmpty || lower == "unknown" || lower == "new user"
    }

    private func enrichWithContactNames() {
        var overrides: [UUID: String] = [:]
        for person in people {
            let needsEnrichment = person.displayName.map { isPlaceholderName($0) } ?? true
            if needsEnrichment, let phone = person.phoneE164,
               let name = contactsManager.name(forPhone: phone) {
                overrides[person.id] = name
            }
        }
        contactNameOverrides = overrides
    }

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
            async let friendsFetch = MeetupService.shared.getFriends()
            async let meetupFetch = MeetupService.shared.getPeopleFromMeetups()
            async let incomingFetch = MeetupService.shared.getPendingIncomingRequests()
            async let outgoingFetch = MeetupService.shared.getPendingOutgoingRequests()
            let (friends, meetupPeople, incoming, outgoing) = try await (friendsFetch, meetupFetch, incomingFetch, outgoingFetch)

            let incomingIds = Set(incoming.map { $0.requester.id })
            let outgoingIds = Set(outgoing.map { $0.addressee.id })

            var seen = Set<UUID>()
            // Friends + meetup people, excluding anyone who has a pending incoming request (not friends yet)
            var combined: [Profile] = (friends + meetupPeople)
                .filter { !incomingIds.contains($0.id) }
                .filter { seen.insert($0.id).inserted }
            // Append outgoing pending addressees (shown with "Pending" badge)
            for req in outgoing where seen.insert(req.addressee.id).inserted {
                combined.append(req.addressee)
            }
            combined.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }

            incomingRequests = incoming
            pendingOutgoingIds = outgoingIds
            people = combined
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func startFriendRequestRealtime() async {
        guard let myId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        let channel = SupabaseManager.shared.client.realtimeV2.channel("friend-requests-\(myId)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "friendships")
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await load()
            enrichWithContactNames()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
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
                else {
                    let resolvedName = isPlaceholderName(user.displayName)
                        ? (contactsManager.name(forPhone: e164) ?? user.displayName)
                        : user.displayName
                    foundUser = FoundUser(id: user.id, displayName: resolvedName, phone: user.phone)
                }
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
            else {
                let resolvedName = isPlaceholderName(user.displayName)
                    ? contact.displayName
                    : user.displayName
                foundUser = FoundUser(id: user.id, displayName: resolvedName, phone: user.phone)
            }
        } else {
            error = "\(contact.displayName) isn't on the app yet"
        }
        isSearching = false
    }

    private func removePerson(_ person: Profile) async {
        do {
            try await MeetupService.shared.removeFriend(userId: person.id)
            people.removeAll { $0.id == person.id }
            pendingOutgoingIds.remove(person.id)
            contactNameOverrides.removeValue(forKey: person.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func acceptRequest(_ request: IncomingFriendRequest) async {
        do {
            try await MeetupService.shared.acceptFriendRequest(friendshipId: request.id)
            incomingRequests.removeAll { $0.id == request.id }
            await load()
            enrichWithContactNames()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func declineRequest(_ request: IncomingFriendRequest) async {
        do {
            try await MeetupService.shared.declineFriendRequest(friendshipId: request.id)
            incomingRequests.removeAll { $0.id == request.id }
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
                await load()
                enrichWithContactNames()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Person Card

private struct PersonCard: View {
    let person: Profile
    let contactName: String?
    let isPending: Bool
    let onRemove: () -> Void

    init(person: Profile, contactName: String?, isPending: Bool = false, onRemove: @escaping () -> Void) {
        self.person = person
        self.contactName = contactName
        self.isPending = isPending
        self.onRemove = onRemove
    }

    private var displayedName: String {
        contactName ?? person.displayName ?? "Unknown"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(personColor(for: person.id).opacity(0.7))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(String(displayedName.prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayedName)
                    .font(.system(size: 13, weight: .semibold))
                if let phone = person.phoneE164 {
                    Text(phone)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isPending {
                Text("Pending")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Button(action: onRemove) {
                    Image(systemName: "person.badge.minus")
                        .font(.system(size: 15))
                        .foregroundStyle(.red.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(displayedName)")
            }
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
            if !isPending {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func personColor(for id: UUID) -> Color {
        Color.participantPalette[abs(id.hashValue) % Color.participantPalette.count]
    }
}
