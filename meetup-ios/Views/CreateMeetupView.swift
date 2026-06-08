import SwiftUI
import CoreLocation
import Supabase

struct CategoryOption: Identifiable {
    let title: String
    let color: Color
    var id: String { title }

    static let presets: [CategoryOption] = [
        CategoryOption(title: "Squad Brunch", color: .coral),
        CategoryOption(title: "Squad Happy Hour", color: .pink),
        CategoryOption(title: "Squad Kickback", color: .teal),
    ]
}

struct CreateMeetupView: View {
    @Environment(\.dismiss) private var dismiss

    // Only state needed at create() time lives here.
    // Keyboard-driven state (search query, phone, contacts) lives in sub-views
    // so typing there never re-renders this body.
    @State private var selectedPlace: SelectedPlace?

    @State private var setTargetTime = false
    @State private var targetTime = CreateMeetupView.defaultPickerTime
    @State private var pickerHour: Int = {
        let h = Calendar.current.component(.hour, from: CreateMeetupView.defaultPickerTime)
        return h % 12 == 0 ? 12 : h % 12
    }()
    @State private var pickerMinute = Calendar.current.component(.minute, from: CreateMeetupView.defaultPickerTime)
    @State private var pickerAmPm = Calendar.current.component(.hour, from: CreateMeetupView.defaultPickerTime) < 12 ? 0 : 1

    private static let defaultPickerTime: Date = {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date().addingTimeInterval(3600))
        comps.minute = ((comps.minute ?? 0) / 15 + 1) * 15
        comps.second = 0
        return cal.date(from: comps) ?? Date().addingTimeInterval(3600)
    }()

    @State private var invitees: [FoundUser] = []
    @State private var isCreating = false
    @State private var selectedCategory: String? = nil
    @State private var customCategoryText = ""
    @State private var showingCustomCategory = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DestinationSection(selectedPlace: $selectedPlace)

                Section {
                    Toggle("Set a target arrival time", isOn: $setTargetTime)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                    if setTargetTime {
                        DatePicker("Date", selection: $targetTime, in: Date()..., displayedComponents: [.date])
                            .foregroundStyle(.white)
                            .tint(Color.coral)
                            .listRowBackground(Color.appSurface)
                        HStack(spacing: 0) {
                            Picker("Hour", selection: $pickerHour) {
                                ForEach(1...12, id: \.self) { h in
                                    Text("\(h)").tag(h)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 60)
                            .clipped()
                            Picker("Minute", selection: $pickerMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 60)
                            .clipped()
                            Picker("AM/PM", selection: $pickerAmPm) {
                                Text("AM").tag(0)
                                Text("PM").tag(1)
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 70)
                            .clipped()
                        }
                        .onChange(of: pickerHour)  { _, _ in syncTimePickers() }
                        .onChange(of: pickerMinute) { _, _ in syncTimePickers() }
                        .onChange(of: pickerAmPm)   { _, _ in syncTimePickers() }
                        .listRowBackground(Color.appSurface)
                    }
                } header: {
                    Text("TIME")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CategoryOption.presets) { option in
                            Button {
                                selectedCategory = (selectedCategory == option.title) ? nil : option.title
                                showingCustomCategory = false
                            } label: {
                                let isSelected = selectedCategory == option.title
                                Text(option.title)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .foregroundStyle(isSelected ? option.color : option.color.opacity(0.5))
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isSelected ? option.color.opacity(0.18) : Color(white: 0.10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(isSelected ? option.color : option.color.opacity(0.25), lineWidth: 1.5)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showingCustomCategory.toggle()
                            if !showingCustomCategory { selectedCategory = nil }
                        } label: {
                            Text("Custom...")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(showingCustomCategory ? Color.coral : Color(white: 0.55))
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(white: 0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(showingCustomCategory ? Color.coral : Color.clear, lineWidth: 1.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.appSurface)
                    if showingCustomCategory {
                        TextField("e.g. Squad Picnic", text: $customCategoryText)
                            .foregroundStyle(.white)
                            .tint(Color.coral)
                            .listRowBackground(Color.appSurface)
                            .onChange(of: customCategoryText) { _, v in
                                selectedCategory = v.isEmpty ? nil : v
                            }
                    }
                } header: {
                    Text("CATEGORY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                InviteSection(invitees: $invitees)

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("New Meetup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(Color(white: 0.15))
                    Group {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            Button {
                                Task { await create() }
                            } label: {
                                Text("Create")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(selectedPlace == nil ? Color.coral.opacity(0.45) : Color.coral)
                                    )
                            }
                            .disabled(selectedPlace == nil)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .accessibilityIdentifier("btn_create_confirm")
                        }
                    }
                    .background(Color.appBackground)
                }
            }
            .preferredColorScheme(.dark)
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func syncTimePickers() {
        let cal = Calendar.current
        let hour24 = (pickerHour % 12) + (pickerAmPm == 1 ? 12 : 0)
        var comps = cal.dateComponents([.year, .month, .day], from: targetTime)
        comps.hour = hour24
        comps.minute = pickerMinute
        comps.second = 0
        if let date = cal.date(from: comps) { targetTime = date }
    }

    private func create() async {
        guard let place = selectedPlace else { return }
        isCreating = true
        error = nil
        do {
            _ = try await MeetupService.shared.createMeetup(
                destinationName: place.name,
                destinationAddress: place.address,
                lat: place.coordinate.latitude,
                lng: place.coordinate.longitude,
                targetArrivalAt: setTargetTime ? targetTime : nil,
                category: selectedCategory,
                invitees: invitees
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isCreating = false
        }
    }
}

// MARK: - Destination Section
// Owns its own searchQuery/searchResults so typing here never re-renders CreateMeetupView.

private struct DestinationSection: View {
    @Binding var selectedPlace: SelectedPlace?
    @State private var searchQuery = ""
    @State private var predictions: [GooglePlacePrediction] = []
    @State private var isLoadingDetails = false

    var body: some View {
        Section {
            if let place = selectedPlace {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.subheadline).bold().foregroundStyle(.white)
                        if let addr = place.address {
                            Text(addr).font(.caption).foregroundStyle(Color(white: 0.6))
                        }
                    }
                    Spacer()
                    Button("Change") {
                        selectedPlace = nil
                        searchQuery = ""
                    }
                    .font(.caption)
                    .foregroundStyle(Color.coral)
                }
                .listRowBackground(Color.appSurface)
            } else {
                TextField("Search for a place", text: $searchQuery)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(Color.coral)
                    .accessibilityIdentifier("field_destination")
                    .listRowBackground(Color.appSurface)
                if isLoadingDetails {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowBackground(Color.appSurface)
                }
                ForEach(predictions) { prediction in
                    Button(action: { Task { await selectPrediction(prediction) } }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prediction.mainText).foregroundStyle(.white)
                            if !prediction.secondaryText.isEmpty {
                                Text(prediction.secondaryText).font(.caption).foregroundStyle(Color(white: 0.6))
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
        } header: {
            Text("DESTINATION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.4))
                .textCase(nil)
        }
        .task(id: searchQuery) {
            guard searchQuery.count >= 2 else { predictions = []; return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await runSearch()
        }
    }

    private func selectPrediction(_ prediction: GooglePlacePrediction) async {
        isLoadingDetails = true
        predictions = []
        if let place = await GooglePlacesService.shared.details(for: prediction) {
            selectedPlace = place
        }
        isLoadingDetails = false
    }

    private func runSearch() async {
        guard selectedPlace == nil, searchQuery.count >= 2 else { predictions = []; return }
        let q = searchQuery
        let results = await GooglePlacesService.shared.autocomplete(query: q)
        guard !Task.isCancelled, searchQuery == q else { return }
        predictions = results
    }
}

// MARK: - Invite Section
// Owns all phone/contacts state so typing here never re-renders CreateMeetupView.
// Phone field stores raw input (no write-back formatting) to avoid the double-render
// loop that the old onChange-writes-inviteePhone pattern caused.

private struct InviteSection: View {
    @Binding var invitees: [FoundUser]

    @State private var inviteePhone = ""
    @State private var foundUser: FoundUser?
    @State private var foundUserStatus: FriendshipStatus = .none
    @State private var isSearchingUser = false
    @State private var isSendingRequest = false
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []
    @State private var error: String?

    private var phoneDigits: String {
        let raw = inviteePhone.hasPrefix("+1") ? String(inviteePhone.dropFirst(2)) : inviteePhone
        return raw.filter(\.isNumber)
    }

    var body: some View {
        Section {
            FriendSuggestionsRow(invitees: $invitees)
                .listRowBackground(Color.appSurface)
            HStack {
                TextField("Name or +1 (646) 946-6861", text: $inviteePhone)
                    .keyboardType(.default)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(Color.coral)
                    .onChange(of: inviteePhone) { _, v in
                        // Single pass — no write-back to inviteePhone, so one render per keystroke.
                        let query: String
                        if v.contains(where: { $0.isLetter }) {
                            query = v
                        } else {
                            let raw = v.hasPrefix("+1") ? String(v.dropFirst(2)) : v
                            query = raw.filter(\.isNumber)
                        }
                        contactSuggestions = query.isEmpty ? [] : Array(contactsManager.search(query).prefix(5))
                    }
                if isSearchingUser {
                    ProgressView()
                } else {
                    Button("Search") { Task { await searchUser() } }
                        .disabled(phoneDigits.count < 10)
                        .foregroundStyle(Color.coral)
                }
            }
            .listRowBackground(Color.appSurface)
            ForEach(contactSuggestions) { contact in
                Button { Task { await selectContact(contact) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName).foregroundStyle(.white)
                        Text(contact.phones.first ?? contact.emails.first ?? "")
                            .font(.caption).foregroundStyle(Color(white: 0.6))
                    }
                }
                .listRowBackground(Color.appSurface)
            }
            if let user = foundUser {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(.subheadline).foregroundStyle(.white)
                            Text(user.phone).font(.caption).foregroundStyle(Color(white: 0.6))
                        }
                        Spacer()
                        foundUserAction(for: user)
                    }
                    if let hint = foundUserHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .listRowBackground(Color.appSurface)
            }
            ForEach(invitees, id: \.id) { invitee in
                HStack {
                    Text(invitee.displayName).foregroundStyle(.white)
                    Spacer()
                    Text(invitee.phone).font(.caption).foregroundStyle(Color(white: 0.6))
                }
                .listRowBackground(Color.appSurface)
            }
            .onDelete { indexSet in invitees.remove(atOffsets: indexSet) }
        } header: {
            Text("INVITE PEOPLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.4))
                .textCase(nil)
        }
        .task { await contactsManager.load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private func foundUserAction(for user: FoundUser) -> some View {
        if isSendingRequest {
            ProgressView()
        } else {
            switch foundUserStatus {
            case .accepted:
                Button("Add") { addInvitee(user) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.coral)
                    .controlSize(.small)
            case .pendingOutgoing:
                Text("Request pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.6))
            case .pendingIncoming:
                Button("Accept request") { Task { await sendFriendRequest(to: user) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.coral)
                    .controlSize(.small)
            case .none:
                Button("Send friend request") { Task { await sendFriendRequest(to: user) } }
                    .buttonStyle(.bordered)
                    .tint(Color.coral)
                    .controlSize(.small)
            }
        }
    }

    private var foundUserHint: String? {
        switch foundUserStatus {
        case .accepted: return nil
        case .pendingOutgoing: return "You can invite them once they accept your friend request."
        case .pendingIncoming: return "They sent you a friend request — accept it to invite them."
        case .none: return "You can only invite friends. Send a request first; they'll be invitable once accepted."
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
                if user.id == myId { error = "That's you!" }
                else if invitees.contains(where: { $0.id == user.id }) { error = "Already added" }
                else {
                    foundUserStatus = try await MeetupService.shared.friendshipStatus(with: user.id)
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

    private func addInvitee(_ user: FoundUser) {
        invitees.append(user)
        foundUser = nil
        foundUserStatus = .none
        inviteePhone = ""
        error = nil
    }

    private func sendFriendRequest(to user: FoundUser) async {
        isSendingRequest = true
        error = nil
        do {
            try await MeetupService.shared.addFriend(userId: user.id)
            // addFriend auto-accepts an existing incoming request; otherwise creates a pending one.
            foundUserStatus = try await MeetupService.shared.friendshipStatus(with: user.id)
        } catch {
            self.error = error.localizedDescription
        }
        isSendingRequest = false
    }

    private func selectContact(_ contact: DeviceContact) async {
        isSearchingUser = true
        contactSuggestions = []
        inviteePhone = ""
        foundUser = nil
        error = nil
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        var found: FoundUser?
        for phone in contact.phones {
            if let user = try? await MeetupService.shared.findUserByPhone(phone) { found = user; break }
        }
        if let user = found {
            if user.id == myId { error = "That's you!" }
            else if invitees.contains(where: { $0.id == user.id }) { error = "Already added" }
            else {
                foundUserStatus = (try? await MeetupService.shared.friendshipStatus(with: user.id)) ?? .none
                foundUser = user
            }
        } else {
            error = "\(contact.displayName) isn't on the app yet"
        }
        isSearchingUser = false
    }
}

// MARK: - Friend Suggestions Row

private struct FriendSuggestionsRow: View {
    @Binding var invitees: [FoundUser]
    @State private var friends: [Profile] = []

    var body: some View {
        Group {
            if !friends.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("From your squad")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.6))
                        .textCase(.uppercase)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(friends) { friend in
                                FriendChip(
                                    friend: friend,
                                    isInvited: invitees.contains(where: { $0.id == friend.id }),
                                    onTap: { toggle(friend) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .task {
            friends = (try? await MeetupService.shared.getFriends()) ?? []
        }
    }

    private func toggle(_ friend: Profile) {
        let user = FoundUser(
            id: friend.id,
            displayName: friend.displayName ?? "Unknown",
            phone: friend.phoneE164 ?? ""
        )
        if let idx = invitees.firstIndex(where: { $0.id == friend.id }) {
            invitees.remove(at: idx)
        } else {
            invitees.append(user)
        }
    }
}

// MARK: - Friend Chip

private struct FriendChip: View {
    let friend: Profile
    let isInvited: Bool
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
                ZStack {
                    Circle()
                        .fill(isInvited ? Color.coral : Color.coral.opacity(0.12))
                        .frame(width: 44, height: 44)
                    if isInvited {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(initial)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.coral)
                    }
                }
                Text(shortName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isInvited ? Color.coral : Color(white: 0.6))
                    .lineLimit(1)
            }
            .frame(width: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isInvited ? "Remove \(shortName)" : "Invite \(shortName)")
    }
}
