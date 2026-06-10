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
    @State private var foundUserStatus: FriendshipStatus = .none
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []
    @State private var contactNameOverrides: [UUID: String] = [:]
    @State private var smartSuggestions: [ProfileSuggestion] = []
    @State private var selectedSuggestion: ProfileSuggestion?
    @State private var selectedDirectMessage: DirectMessageRoute?
    @Environment(NavigationState.self) private var navState
    @Environment(AppSettings.self) private var settings

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
                                                    .scaledFont(size: 16, weight: .bold)
                                                    .foregroundStyle(Color.coral)
                                            }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(contact.displayName)
                                                .scaledFont(size: 13, weight: .semibold)
                                                .foregroundStyle(.primary)
                                            Text(contact.phones.first ?? contact.emails.first ?? "")
                                                .scaledFont(size: 11)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color(white: 0.15), lineWidth: 1)
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
                                let isPending = pendingOutgoingIds.contains(person.id)
                                PersonCard(
                                    person: person,
                                    contactName: contactNameOverrides[person.id],
                                    isPending: isPending,
                                    onMessage: isPending ? nil : {
                                        Task { await openDirectMessage(with: person) }
                                    }
                                ) {
                                    Task { await removePerson(person) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    } else if hasLoaded && people.isEmpty && incomingRequests.isEmpty
                                && contactSuggestions.isEmpty && foundUser == nil
                                && smartSuggestions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.circle")
                                .scaledFont(size: 48)
                                .foregroundStyle(Color.coral.opacity(0.4))
                                .padding(.top, 48)
                            Text("No connections yet")
                                .scaledFont(size: 16, weight: .bold)
                                .foregroundStyle(.white)
                            Text("People you've had meetups with will appear here.")
                                .scaledFont(size: 13)
                                .foregroundStyle(Color(white: 0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                    } else if !hasLoaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    }

                    // "People you may know" — shown when friends list is small (<3)
                    if hasLoaded && people.filter({ !pendingOutgoingIds.contains($0.id) }).count < 3
                        && !smartSuggestions.isEmpty {
                        sectionLabel("People You May Know")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        LazyVStack(spacing: 8) {
                            ForEach(smartSuggestions) { suggestion in
                                SuggestionCard(suggestion: suggestion) {
                                    selectedSuggestion = suggestion
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("People")
            .preferredColorScheme(.dark)
            .task {
                await load()
                await loadContactsIfEnabled()
                enrichWithContactNames()
                refreshSuggestions()
                await loadSmartSuggestions()
                await startFriendRequestRealtime()
            }
            .onChange(of: settings.contactsEnabled) { _, _ in
                Task {
                    await loadContactsIfEnabled()
                    enrichWithContactNames()
                    refreshSuggestions()
                    await loadSmartSuggestions()
                }
            }
            .sheet(item: $selectedSuggestion) { suggestion in
                SuggestionProfileSheet(
                    suggestion: suggestion,
                    onAddFriend: {
                        Task { await addSuggestion(suggestion) }
                        selectedSuggestion = nil
                    },
                    onDismiss: { selectedSuggestion = nil }
                )
            }
            .sheet(item: $selectedDirectMessage) { route in
                NavigationStack {
                    MessageThreadView(conversationId: route.id, friend: route.friend)
                }
            }
            .onChange(of: navState.showFriendRequests) { _, show in
                guard show else { return }
                navState.showFriendRequests = false
                // Reload to pick up any new incoming requests, then the
                // "Friend Requests" section at the top of the list will be visible.
                Task {
                    await load()
                    enrichWithContactNames()
                }
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
                .scaledFont(size: 15)
                .foregroundStyle(.secondary)

            TextField("Name or +1 (646) 946-6861", text: $phoneSearch)
                .keyboardType(.default)
                .autocorrectionDisabled()
                .onChange(of: phoneSearch) { _, v in
                    if v.contains(where: { $0.isLetter }) {
                        contactSuggestions = settings.contactsEnabled
                            ? Array(contactsManager.search(v).prefix(5))
                            : []
                    } else {
                        let raw = v.hasPrefix("+1") ? String(v.dropFirst(2)) : v
                        let digitsOnly = String(raw.filter { $0.isNumber }.prefix(10))
                        let formatted = PhoneFormatter.formatWithCountryCode(digitsOnly)
                        if phoneSearch != formatted {
                            phoneSearch = formatted
                        } else {
                            contactSuggestions = settings.contactsEnabled
                                ? Array(contactsManager.search(digitsOnly).prefix(5))
                                : []
                        }
                    }
                }

            if isSearching {
                ProgressView().controlSize(.small)
            } else if !phoneSearch.isEmpty {
                Button("Search") { Task { await searchUser() } }
                    .scaledFont(size: 14, weight: .semibold)
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
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.coral)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .scaledFont(size: 14, weight: .semibold)
                Text(user.phone)
                    .scaledFont(size: 12)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            foundUserAction(for: user)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.coral.opacity(0.08), radius: 8, y: 2)
    }

    @ViewBuilder
    private func foundUserAction(for user: FoundUser) -> some View {
        if isAdding {
            ProgressView().tint(.white).scaleEffect(0.8)
                .frame(width: 72, height: 30)
                .background(Color.coral)
                .clipShape(Capsule())
        } else {
            switch foundUserStatus {
            case .accepted:
                statusBadge("Friends")
            case .pendingOutgoing:
                statusBadge("Pending")
            case .pendingIncoming:
                Button("Accept") {
                    addFriend(user)
                }
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.coral)
                .clipShape(Capsule())
            case .none:
                Button("Add") {
                    addFriend(user)
                }
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.coral)
                .clipShape(Capsule())
            }
        }
    }

    private func statusBadge(_ title: String) -> some View {
        Text(title)
            .scaledFont(size: 12, weight: .bold)
            .foregroundStyle(Color(white: 0.65))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private func incomingRequestCard(_ request: IncomingFriendRequest) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.coral.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Text(String((request.requester.displayName ?? "?").prefix(1)).uppercased())
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.coral)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(request.requester.displayName ?? "Unknown")
                    .scaledFont(size: 14, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let phone = request.requester.phoneE164 {
                    Text(phone)
                        .scaledFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                Button {
                    Task { await acceptRequest(request) }
                } label: {
                    Text("✅")
                        .scaledFont(size: 24)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await declineRequest(request) }
                } label: {
                    Text("❌")
                        .scaledFont(size: 24)
                }
                .buttonStyle(.plain)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.coral.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.coral.opacity(0.08), radius: 8, y: 2)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .scaledFont(size: 10, weight: .bold)
            .foregroundStyle(Color(white: 0.45))
    }

    // MARK: - Logic

    private func isPlaceholderName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.isEmpty || lower == "unknown" || lower == "new user"
    }

    private func enrichWithContactNames() {
        guard settings.contactsEnabled else {
            contactNameOverrides = [:]
            return
        }
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
        guard settings.contactsEnabled else { contactSuggestions = []; return }
        guard !phoneSearch.isEmpty else { contactSuggestions = []; return }
        if phoneSearch.contains(where: { $0.isLetter }) {
            contactSuggestions = Array(contactsManager.search(phoneSearch).prefix(5))
        } else {
            let raw = phoneSearch.hasPrefix("+1") ? String(phoneSearch.dropFirst(2)) : phoneSearch
            let digits = raw.filter { $0.isNumber }
            contactSuggestions = digits.isEmpty ? [] : Array(contactsManager.search(digits).prefix(5))
        }
    }

    private func loadContactsIfEnabled() async {
        guard settings.contactsEnabled else {
            contactsManager.clear()
            contactSuggestions = []
            contactNameOverrides = [:]
            return
        }
        await contactsManager.load()
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
            async let incomingFetch = MeetupService.shared.getPendingIncomingRequests()
            async let outgoingFetch = MeetupService.shared.getPendingOutgoingRequests()
            let (friends, incoming, outgoing) = try await (friendsFetch, incomingFetch, outgoingFetch)
            let meetupPeople: [Profile] = []

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
        do {
            for await _ in changes {
                try Task.checkCancellation()
                await load()
                enrichWithContactNames()
            }
        } catch {
            // CancellationError — fall through to removeChannel
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }

    private func searchUser() async {
        guard let e164 = PhoneFormatter.toE164(phoneSearch) else {
            error = "Enter a valid 10-digit US phone number"
            return
        }
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        isSearching = true
        foundUser = nil
        foundUserStatus = .none
        error = nil
        do {
            if let user = try await MeetupService.shared.findUserByPhone(e164) {
                if user.id == myId { error = "That's you!" }
                else {
                    let resolvedName = isPlaceholderName(user.displayName)
                        ? (contactsManager.name(forPhone: e164) ?? user.displayName)
                        : user.displayName
                    foundUserStatus = try await MeetupService.shared.friendshipStatus(with: user.id)
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
        foundUserStatus = .none
        error = nil
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        var found: FoundUser?
        for phone in contact.phones {
            if let user = try? await MeetupService.shared.findUserByPhone(phone) { found = user; break }
        }
        if let user = found {
            if user.id == myId { error = "That's you!" }
            else {
                let resolvedName = isPlaceholderName(user.displayName)
                    ? contact.displayName
                    : user.displayName
                foundUserStatus = (try? await MeetupService.shared.friendshipStatus(with: user.id)) ?? .none
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
            await load()
            enrichWithContactNames()
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
        guard !isAdding else { return }
        isAdding = true
        Task {
            do {
                try await MeetupService.shared.addFriend(userId: user.id)
                phoneSearch = ""
                foundUser = nil
                foundUserStatus = .none
                // Optimistically update the visible list, then reload from Supabase
                // so accepted-vs-pending state matches the canonical friendship row.
                let latestStatus = try await MeetupService.shared.friendshipStatus(with: user.id)
                if latestStatus == .pendingOutgoing {
                    pendingOutgoingIds.insert(user.id)
                } else {
                    pendingOutgoingIds.remove(user.id)
                }
                if !people.contains(where: { $0.id == user.id }) {
                    let placeholder = Profile(
                        id: user.id, displayName: user.displayName,
                        phoneE164: user.phone, email: nil
                    )
                    people.append(placeholder)
                    people.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }
                }
                await load()
                enrichWithContactNames()
            } catch {
                self.error = error.localizedDescription
            }
            isAdding = false
        }
    }

    private func loadSmartSuggestions() async {
        let existingIds = Set(people.map { $0.id })
        do {
            let results: [ProfileSuggestion]
            if settings.contactsEnabled {
                results = try await SuggestionsService.shared.fetchSuggestions(
                    contactsManager: contactsManager,
                    existingFriendIds: existingIds
                )
            } else {
                results = try await SuggestionsService.shared.fetchFriendsOfFriends(existingFriendIds: existingIds)
            }
            smartSuggestions = results
        } catch is CancellationError {
            return
        } catch {
            // Non-fatal: silently swallow suggestion errors
        }
    }

    private func addSuggestion(_ suggestion: ProfileSuggestion) async {
        do {
            try await MeetupService.shared.addFriend(userId: suggestion.profile.id)
            smartSuggestions.removeAll { $0.id == suggestion.id }
            await load()
            enrichWithContactNames()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openDirectMessage(with person: Profile) async {
        do {
            let conversationId = try await DirectMessageService.shared.getOrCreateConversation(with: person.id)
            selectedDirectMessage = DirectMessageRoute(id: conversationId, friend: person)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DirectMessageRoute: Identifiable {
    let id: UUID
    let friend: Profile
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    let suggestion: ProfileSuggestion
    let onTap: () -> Void

    private var displayedName: String {
        suggestion.profile.displayName ?? "Unknown"
    }

    private var subtitleText: String {
        switch suggestion.reason {
        case .inContacts:
            return "In your contacts"
        case .mutualFriends(let count):
            return count == 1 ? "1 mutual friend" : "\(count) mutual friends"
        }
    }

    private func avatarColor(for id: UUID) -> Color {
        Color.participantPalette[abs(id.hashValue) % Color.participantPalette.count]
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(avatarColor(for: suggestion.profile.id).opacity(0.7))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Text(String(displayedName.prefix(1)).uppercased())
                            .scaledFont(size: 17, weight: .bold)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedName)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(subtitleText)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.coral.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.coral.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestion Profile Sheet

private struct SuggestionProfileSheet: View {
    let suggestion: ProfileSuggestion
    let onAddFriend: () -> Void
    let onDismiss: () -> Void

    private var displayedName: String {
        suggestion.profile.displayName ?? "Unknown"
    }

    private var subtitleText: String {
        switch suggestion.reason {
        case .inContacts:
            return "In your contacts"
        case .mutualFriends(let count):
            return count == 1 ? "1 mutual friend" : "\(count) mutual friends"
        }
    }

    private func avatarColor(for id: UUID) -> Color {
        Color.participantPalette[abs(id.hashValue) % Color.participantPalette.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // Avatar
            Circle()
                .fill(avatarColor(for: suggestion.profile.id).opacity(0.7))
                .frame(width: 80, height: 80)
                .overlay {
                    Text(String(displayedName.prefix(1)).uppercased())
                        .scaledFont(size: 32, weight: .bold)
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 16)

            // Name
            Text(displayedName)
                .scaledFont(size: 22, weight: .bold)
                .padding(.bottom, 4)

            // Reason badge
            HStack(spacing: 4) {
                Image(systemName: suggestion.reason == .inContacts ? "person.crop.circle" : "person.2")
                    .scaledFont(size: 12)
                Text(subtitleText)
                    .scaledFont(size: 13, weight: .semibold)
            }
            .foregroundStyle(Color.coral)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.coral.opacity(0.12))
            .clipShape(Capsule())
            .padding(.bottom, 8)

            // Phone
            if let phone = suggestion.profile.phoneE164 {
                Text(phone)
                    .scaledFont(size: 14)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)
            } else {
                Spacer().frame(height: 32)
            }

            // Add Friend button
            Button(action: onAddFriend) {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Dismiss button
            Button("Not Now", action: onDismiss)
                .scaledFont(size: 15)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background(Color.appSurface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Person Card

private struct PersonCard: View {
    let person: Profile
    let contactName: String?
    let isPending: Bool
    let onMessage: (() -> Void)?
    let onRemove: () -> Void

    init(
        person: Profile,
        contactName: String?,
        isPending: Bool = false,
        onMessage: (() -> Void)? = nil,
        onRemove: @escaping () -> Void
    ) {
        self.person = person
        self.contactName = contactName
        self.isPending = isPending
        self.onMessage = onMessage
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
                        .scaledFont(size: 15, weight: .bold)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayedName)
                    .scaledFont(size: 13, weight: .semibold)
                if let phone = person.phoneE164 {
                    Text(phone)
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isPending {
                HStack(spacing: 6) {
                    Text("Pending")
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(size: 18)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel request to \(displayedName)")
                }
            } else {
                HStack(spacing: 12) {
                    if let onMessage {
                        Button(action: onMessage) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .scaledFont(size: 15)
                                .foregroundStyle(Color.coral)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Message \(displayedName)")
                    }

                    Button(action: onRemove) {
                        Image(systemName: "person.badge.minus")
                            .scaledFont(size: 15)
                            .foregroundStyle(.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(displayedName)")
                }
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
            Button(role: .destructive, action: onRemove) {
                Label(isPending ? "Cancel Request" : "Remove", systemImage: isPending ? "xmark" : "trash")
            }
        }
    }

    private func personColor(for id: UUID) -> Color {
        Color.participantPalette[abs(id.hashValue) % Color.participantPalette.count]
    }
}
