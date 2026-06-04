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

                Section("Time") {
                    Toggle("Set a target arrival time", isOn: $setTargetTime)
                    if setTargetTime {
                        DatePicker("Date", selection: $targetTime, in: Date()..., displayedComponents: [.date])
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
                    }
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CategoryOption.presets) { option in
                            Button {
                                selectedCategory = (selectedCategory == option.title) ? nil : option.title
                                showingCustomCategory = false
                            } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .foregroundStyle(selectedCategory == option.title ? .white : option.color)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedCategory == option.title ? option.color : option.color.opacity(0.12))
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
                                .foregroundStyle(showingCustomCategory ? .white : .purple)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(showingCustomCategory ? Color.purple : Color.purple.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    if showingCustomCategory {
                        TextField("e.g. Squad Picnic", text: $customCategoryText)
                            .onChange(of: customCategoryText) { _, v in
                                selectedCategory = v.isEmpty ? nil : v
                            }
                    }
                }

                InviteSection(invitees: $invitees)

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Meetup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .buttonStyle(.glassProminent)
                            .disabled(selectedPlace == nil)
                            .accessibilityIdentifier("btn_create_confirm")
                    }
                }
            }
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
        Section("Destination") {
            if let place = selectedPlace {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.subheadline).bold()
                        if let addr = place.address {
                            Text(addr).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Change") {
                        selectedPlace = nil
                        searchQuery = ""
                    }
                    .font(.caption)
                }
            } else {
                TextField("Search for a place", text: $searchQuery)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("field_destination")
                if isLoadingDetails {
                    ProgressView().frame(maxWidth: .infinity)
                }
                ForEach(predictions) { prediction in
                    Button(action: { Task { await selectPrediction(prediction) } }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prediction.mainText).foregroundStyle(.primary)
                            if !prediction.secondaryText.isEmpty {
                                Text(prediction.secondaryText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
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
    @State private var isSearchingUser = false
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []
    @State private var error: String?

    private var phoneDigits: String {
        let raw = inviteePhone.hasPrefix("+1") ? String(inviteePhone.dropFirst(2)) : inviteePhone
        return raw.filter(\.isNumber)
    }

    var body: some View {
        Section("Invite people") {
            HStack {
                TextField("Name or +1 (646) 946-6861", text: $inviteePhone)
                    .keyboardType(.default)
                    .autocorrectionDisabled()
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
                }
            }
            ForEach(contactSuggestions) { contact in
                Button { Task { await selectContact(contact) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName).foregroundStyle(.primary)
                        Text(contact.phones.first ?? contact.emails.first ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let user = foundUser {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(.subheadline)
                        Text(user.phone).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") { addInvitee(user) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            ForEach(invitees, id: \.id) { invitee in
                HStack {
                    Text(invitee.displayName)
                    Spacer()
                    Text(invitee.phone).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { indexSet in invitees.remove(atOffsets: indexSet) }
        }
        .task { await contactsManager.load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
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
                else { foundUser = user }
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
        inviteePhone = ""
        error = nil
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
        if found == nil {
            for email in contact.emails {
                if let user = try? await MeetupService.shared.findUserByEmail(email) { found = user; break }
            }
        }
        if let user = found {
            if user.id == myId { error = "That's you!" }
            else if invitees.contains(where: { $0.id == user.id }) { error = "Already added" }
            else { addInvitee(user) }
        } else {
            error = "\(contact.displayName) isn't on the app yet"
        }
        isSearchingUser = false
    }
}
