import SwiftUI
import MapKit
import Supabase

struct CreateMeetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedPlace: MKMapItem?

    @State private var setTargetTime = false
    @State private var targetTime = Date().addingTimeInterval(3600)

    @State private var inviteePhone = ""
    @State private var foundUser: FoundUser?
    @State private var isSearchingUser = false
    @State private var invitees: [FoundUser] = []
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []

    @State private var isCreating = false
    @State private var selectedCategory: String? = nil
    @State private var customCategoryText = ""
    @State private var showingCustomCategory = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    if let place = selectedPlace {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name ?? "").font(.subheadline).bold()
                                Text(place.name ?? "").font(.caption).foregroundStyle(.secondary)
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
                        ForEach(searchResults, id: \.self) { item in
                            Button(action: { selectPlace(item) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown").foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }

                Section("Time") {
                    Toggle("Set a target arrival time", isOn: $setTargetTime)
                    if setTargetTime {
                        DatePicker("Date", selection: $targetTime, in: Date()..., displayedComponents: [.date])
                        HStack {
                            Text("Time")
                            Spacer()
                            Picker("Time", selection: Binding(
                                get: { targetTime },
                                set: { newTime in
                                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: newTime)
                                    let minute = Calendar.current.component(.minute, from: newTime)
                                    let roundedMinute = (minute / 15) * 15
                                    if let date = Calendar.current.date(bySettingHour: components.hour ?? 0, minute: roundedMinute, second: 0, of: targetTime) {
                                        targetTime = date
                                    }
                                }
                            )) {
                                ForEach(0..<(24 * 4), id: \.self) { index in
                                    let hour = index / 4
                                    let minute = (index % 4) * 15
                                    let label = String(format: "%02d:%02d", hour, minute)
                                    Text(label).tag(generateTime(hour: hour, minute: minute))
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                    }
                }

                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["Squad Brunch", "Squad Happy Hour", "Squad Kickback"], id: \.self) { cat in
                                Button(cat) {
                                    if selectedCategory == cat {
                                        selectedCategory = nil
                                        showingCustomCategory = false
                                    } else {
                                        selectedCategory = cat
                                        showingCustomCategory = false
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedCategory == cat ? .accentColor : .secondary)
                            }
                            Button("Custom...") {
                                showingCustomCategory.toggle()
                                if !showingCustomCategory { selectedCategory = nil }
                            }
                            .buttonStyle(.bordered)
                            .tint(showingCustomCategory ? .accentColor : .secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    if showingCustomCategory {
                        TextField("e.g. Squad Picnic", text: $customCategoryText)
                            .onChange(of: customCategoryText) { _, v in
                                selectedCategory = v.isEmpty ? nil : v
                            }
                    }
                }

                Section("Invite people") {
                    HStack {
                        TextField("Name or +1 (646) 946-6861", text: $inviteePhone)
                            .keyboardType(.default)
                            .autocorrectionDisabled()
                            .onChange(of: inviteePhone) { _, v in
                                if v.contains(where: { $0.isLetter }) {
                                    contactSuggestions = Array(contactsManager.search(v).prefix(5))
                                } else {
                                    let raw = v.hasPrefix("+1") ? String(v.dropFirst(2)) : v
                                    let digitsOnly = String(raw.filter { $0.isNumber }.prefix(10))
                                    let formatted = formatPhone(digitsOnly)
                                    if inviteePhone != formatted {
                                        inviteePhone = formatted
                                    } else {
                                        contactSuggestions = Array(contactsManager.search(digitsOnly).prefix(5))
                                    }
                                }
                            }
                        if isSearchingUser {
                            ProgressView()
                        } else {
                            Button("Search") { Task { await searchUser() } }
                                .disabled({
                                    let raw = inviteePhone.hasPrefix("+1") ? String(inviteePhone.dropFirst(2)) : inviteePhone
                                    return raw.filter { $0.isNumber }.count < 10
                                }())
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
                    }
                }
            }
            .task(id: searchQuery) {
                if searchQuery.count < 2 {
                    searchResults = []
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    return
                }
                await performSearch()
            }
            .task {
                await contactsManager.load()
                refreshSuggestions()
            }
        }
    }

    private func selectPlace(_ item: MKMapItem) {
        selectedPlace = item
        searchResults = []
        searchQuery = item.name ?? ""
    }

    private func performSearch() async {
        guard selectedPlace == nil else { return }
        guard searchQuery.count >= 2 else {
            searchResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        guard let response = try? await MKLocalSearch(request: request).start(),
              !Task.isCancelled else { return }
        searchResults = Array(response.mapItems.prefix(5))
    }

    private func refreshSuggestions() {
        guard !inviteePhone.isEmpty else { contactSuggestions = []; return }
        if inviteePhone.contains(where: { $0.isLetter }) {
            contactSuggestions = Array(contactsManager.search(inviteePhone).prefix(5))
        } else {
            let raw = inviteePhone.hasPrefix("+1") ? String(inviteePhone.dropFirst(2)) : inviteePhone
            let digits = raw.filter { $0.isNumber }
            contactSuggestions = digits.isEmpty ? [] : Array(contactsManager.search(digits).prefix(5))
        }
    }

    private func formatPhone(_ digits: String) -> String {
        switch digits.count {
        case 0:     return ""
        case 1...3: return "+1 (\(digits)"
        case 4...6: return "+1 (\(digits.prefix(3))) \(digits.dropFirst(3))"
        default:    return "+1 (\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
        }
    }

    private func generateTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: targetTime)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? targetTime
    }

    private func searchUser() async {
        let raw = inviteePhone.hasPrefix("+1") ? String(inviteePhone.dropFirst(2)) : inviteePhone
        let digits = raw.filter { $0.isNumber }
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
                } else if invitees.contains(where: { $0.id == user.id }) {
                    error = "Already added"
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
            else { foundUser = user }
        } else {
            error = "\(contact.displayName) isn't on the app yet"
        }
        isSearchingUser = false
    }

    private func create() async {
        guard let place = selectedPlace else { return }
        let location = place.location
        let coord = location.coordinate
        isCreating = true
        error = nil
        do {
            _ = try await MeetupService.shared.createMeetup(
                destinationName: place.name ?? "Meeting Point",
                destinationAddress: place.name,
                lat: coord.latitude,
                lng: coord.longitude,
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
