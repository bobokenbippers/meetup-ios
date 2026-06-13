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
    private let liveMeetups: [Meetup]

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
    @State private var conflictingMeetup: Meetup?
    @State private var error: String?

    private var chosenCategory: String {
        selectedCategory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? selectedCategory!
            : "Squad plan"
    }

    private var createButtonTitle: String {
        guard let selectedPlace else { return "Pick a place to continue" }
        let inviteCount = invitees.count
        if inviteCount == 0 { return "Create at \(selectedPlace.name)" }
        return "Create for \(inviteCount + 1) people"
    }

    /// Opens blank by default; pass a `prefill` (e.g. from a tapped nearby-event card)
    /// to seed the destination, time, and category from a real event.
    init(prefill: EventPrefill? = nil, liveMeetups: [Meetup] = []) {
        self.liveMeetups = liveMeetups
        guard let prefill else { return }
        let effectiveTime = prefill.date ?? CreateMeetupView.defaultPickerTime
        let hour = Calendar.current.component(.hour, from: effectiveTime)
        _selectedPlace = State(initialValue: prefill.place)
        _setTargetTime = State(initialValue: prefill.date != nil)
        _targetTime = State(initialValue: effectiveTime)
        _pickerHour = State(initialValue: hour % 12 == 0 ? 12 : hour % 12)
        _pickerMinute = State(initialValue: Calendar.current.component(.minute, from: effectiveTime))
        _pickerAmPm = State(initialValue: hour < 12 ? 0 : 1)

        let isPreset = CategoryOption.presets.contains { $0.title == prefill.title }
        _selectedCategory = State(initialValue: prefill.title)
        _customCategoryText = State(initialValue: isPreset ? "" : prefill.title)
        _showingCustomCategory = State(initialValue: !isPreset)
    }

    var body: some View {
        NavigationStack {
            Form {
                CreatePlanSummary(
                    place: selectedPlace,
                    targetTime: setTargetTime ? targetTime : nil,
                    category: chosenCategory,
                    invitees: invitees
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                DestinationSection(selectedPlace: $selectedPlace)

                Section {
                    Toggle("Set a target arrival time", isOn: $setTargetTime)
                        .tint(Color.coral)
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)
                    TimePresetRow(
                        targetTime: $targetTime,
                        setTargetTime: $setTargetTime,
                        onChange: syncPickerState
                    )
                    .listRowBackground(Color.appSurface)
                    if setTargetTime {
                        DatePicker("Date", selection: $targetTime, in: Date()..., displayedComponents: [.date])
                            .foregroundStyle(DS.Color.textPrimary)
                            .tint(Color.coral)
                            .listRowBackground(Color.appSurface)
                            .onChange(of: targetTime) { _, _ in syncPickerState() }
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
                        .foregroundStyle(DS.Color.textSecondary)
                        .textCase(nil)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CategoryOption.presets) { option in
                            Button {
                                selectedCategory = (selectedCategory == option.title) ? nil : option.title
                                showingCustomCategory = false
                            } label: {
                                CategorySelectionTile(
                                    title: option.title,
                                    color: option.color,
                                    isSelected: selectedCategory == option.title
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showingCustomCategory.toggle()
                            if !showingCustomCategory { selectedCategory = nil }
                        } label: {
                            CategorySelectionTile(
                                title: "Custom...",
                                color: .coral,
                                isSelected: showingCustomCategory,
                                systemImage: "text.cursor"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.appSurface)
                    if showingCustomCategory {
                        TextField("e.g. Squad Picnic", text: $customCategoryText)
                            .foregroundStyle(DS.Color.textPrimary)
                            .tint(Color.coral)
                            .listRowBackground(Color.appSurface)
                            .onChange(of: customCategoryText) { _, v in
                                selectedCategory = v.isEmpty ? nil : v
                            }
                    }
                } header: {
                    Text("CATEGORY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.textSecondary)
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
                                createTapped()
                            } label: {
                                Text(createButtonTitle)
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

            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .alert("Possible conflict", isPresented: Binding(
                get: { conflictingMeetup != nil },
                set: { if !$0 { conflictingMeetup = nil } }
            )) {
                Button("Cancel", role: .cancel) { conflictingMeetup = nil }
                Button("Create Anyway") {
                    let meetup = conflictingMeetup
                    conflictingMeetup = nil
                    Task { await create(allowConflict: true, conflictToIgnore: meetup?.id) }
                }
            } message: {
                if let conflictingMeetup {
                    Text("You already have \(conflictingMeetup.destinationName) live around this time.")
                } else {
                    Text("You already have a live meetup around this time.")
                }
            }
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

    private func syncPickerState() {
        let hour = Calendar.current.component(.hour, from: targetTime)
        pickerHour = hour % 12 == 0 ? 12 : hour % 12
        pickerMinute = Calendar.current.component(.minute, from: targetTime)
        pickerAmPm = hour < 12 ? 0 : 1
    }

    private func createTapped() {
        if let conflict = findConflict(), conflict.id != conflictingMeetup?.id {
            conflictingMeetup = conflict
            return
        }
        Task { await create() }
    }

    private func findConflict(ignoring ignoredId: UUID? = nil) -> Meetup? {
        let proposedTime = setTargetTime ? targetTime : Date()
        let proposedStart = setTargetTime ? proposedTime.addingTimeInterval(-2 * 3600) : proposedTime
        let proposedEnd = setTargetTime ? proposedTime.addingTimeInterval(2 * 3600) : proposedTime.addingTimeInterval(4 * 3600)
        return liveMeetups.first { meetup in
            guard meetup.id != ignoredId else { return false }
            guard meetup.status == "active", Date() <= meetup.endsAt.addingTimeInterval(2 * 3600) else { return false }
            let liveStart = meetup.startsAt
            let liveEnd = meetup.endsAt.addingTimeInterval(2 * 3600)
            return proposedStart <= liveEnd && proposedEnd >= liveStart
        }
    }

    private func create(allowConflict: Bool = false, conflictToIgnore: UUID? = nil) async {
        guard let place = selectedPlace else { return }
        if !allowConflict, let conflict = findConflict(ignoring: conflictToIgnore) {
            conflictingMeetup = conflict
            return
        }
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

private struct CreatePlanSummary: View {
    let place: SelectedPlace?
    let targetTime: Date?
    let category: String
    let invitees: [FoundUser]

    private var timeText: String {
        guard let targetTime else { return "Start when everyone is ready" }
        return targetTime.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var peopleText: String {
        let total = invitees.count + 1
        return total == 1 ? "Just you for now" : "\(total) people"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(meetupCategoryEmoji(category))
                    .scaledFont(size: 28)
                    .frame(width: 46, height: 46)
                    .background(Color.coral.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(place?.name ?? "Where are we meeting?")
                        .scaledFont(size: 20, weight: .bold)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                    Text(category)
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.coral)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                CreateSummaryPill(systemImage: "clock", title: timeText)
                CreateSummaryPill(systemImage: "person.2.fill", title: peopleText)
            }

            if !invitees.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(invitees, id: \.id) { invitee in
                            Label(invitee.displayName, systemImage: "checkmark.circle.fill")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(DS.Color.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.appSurface)
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.coral.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct CreateSummaryPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .scaledFont(size: 11, weight: .semibold)
            .foregroundStyle(DS.Color.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }
}

private struct TimePresetRow: View {
    @Binding var targetTime: Date
    @Binding var setTargetTime: Bool
    let onChange: () -> Void

    private let presets: [TimePreset] = [
        .init(title: "Now", minutesFromNow: 0),
        .init(title: "30 min", minutesFromNow: 30),
        .init(title: "1 hour", minutesFromNow: 60),
        .init(title: "Tonight", minutesFromNow: nil),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button {
                        targetTime = preset.date()
                        setTargetTime = true
                        onChange()
                    } label: {
                        Text(preset.title)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(DS.Color.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Time presets")
    }
}

private struct TimePreset: Identifiable {
    let title: String
    let minutesFromNow: Int?

    var id: String { title }

    func date() -> Date {
        if let minutesFromNow {
            return Self.roundToQuarterHour(Date().addingTimeInterval(TimeInterval(minutesFromNow * 60)))
        }

        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 19
        comps.minute = 0
        comps.second = 0
        let tonight = calendar.date(from: comps) ?? now.addingTimeInterval(3 * 3600)
        if tonight > now { return tonight }
        return calendar.date(byAdding: .day, value: 1, to: tonight) ?? now.addingTimeInterval(24 * 3600)
    }

    private static func roundToQuarterHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let rounded = Int((Double(minute) / 15.0).rounded(.up)) * 15
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        comps.minute = rounded % 60
        if rounded == 60 { comps.hour = (comps.hour ?? 0) + 1 }
        comps.second = 0
        return calendar.date(from: comps) ?? date
    }
}

private struct CategorySelectionTile: View {
    let title: String
    let color: Color
    let isSelected: Bool
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .scaledFont(size: 13, weight: .semibold)
            }

            Text(title)
                .scaledFont(size: 14, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .scaledFont(size: 13, weight: .bold)
            }
        }
        .foregroundStyle(isSelected ? .white : Color(white: 0.88))
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? color.opacity(0.30) : Color(white: 0.145))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? color : color.opacity(0.55), lineWidth: isSelected ? 2 : 1.25)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Destination Section
// Owns its own searchQuery/searchResults so typing here never re-renders CreateMeetupView.

private struct DestinationSection: View {
    @Binding var selectedPlace: SelectedPlace?
    @State private var searchQuery = ""
    @State private var predictions: [PlaceSearchResult] = []
    @State private var isLoadingDetails = false
    @State private var searchError: String?

    var body: some View {
        Section {
            if let place = selectedPlace {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.subheadline).bold().foregroundStyle(DS.Color.textPrimary)
                        if let addr = place.address {
                            Text(addr).font(.caption).foregroundStyle(DS.Color.textSecondary)
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
                    .foregroundStyle(DS.Color.textPrimary)
                    .tint(Color.coral)
                    .accessibilityIdentifier("field_destination")
                    .listRowBackground(Color.appSurface)
                if isLoadingDetails {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowBackground(Color.appSurface)
                }
                if let searchError {
                    Text(searchError)
                        .font(.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .listRowBackground(Color.appSurface)
                }
                ForEach(predictions) { prediction in
                    Button(action: { selectPrediction(prediction) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prediction.mainText).foregroundStyle(DS.Color.textPrimary)
                            if !prediction.secondaryText.isEmpty {
                                Text(prediction.secondaryText).font(.caption).foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
        } header: {
            Text("DESTINATION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .textCase(nil)
        }
        .task(id: searchQuery) {
            guard searchQuery.count >= 2 else {
                predictions = []
                searchError = nil
                return
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await runSearch()
        }
    }

    private func selectPrediction(_ prediction: PlaceSearchResult) {
        predictions = []
        searchError = nil
        selectedPlace = prediction.place
    }

    private func runSearch() async {
        guard selectedPlace == nil, searchQuery.count >= 2 else { predictions = []; return }
        let q = searchQuery
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        let results = await PlaceSearchService.shared.search(query: q, near: LocationManager.shared.location)
        guard !Task.isCancelled, searchQuery == q else { return }
        predictions = results
        searchError = results.isEmpty ? PlaceSearchService.shared.unavailableMessage : nil
    }
}

// MARK: - Invite Section
// Owns all phone/contacts state so typing here never re-renders CreateMeetupView.
// Phone field stores raw input (no write-back formatting) to avoid the double-render
// loop that the old onChange-writes-inviteePhone pattern caused.

private struct InviteSection: View {
    @Binding var invitees: [FoundUser]

    @Environment(AppSettings.self) private var settings

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
                    .foregroundStyle(DS.Color.textPrimary)
                    .tint(Color.coral)
                    .onChange(of: inviteePhone) { _, v in
                        refreshContactSuggestions(for: v)
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
                        Text(contact.displayName).foregroundStyle(DS.Color.textPrimary)
                        Text(contact.phones.first ?? contact.emails.first ?? "")
                            .font(.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
                .listRowBackground(Color.appSurface)
            }
            if let user = foundUser {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ProfileAvatarView(
                            displayName: user.displayName,
                            avatarUrl: user.avatarUrl,
                            userId: user.id,
                            size: 38,
                            fontSize: 15
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(.subheadline).foregroundStyle(DS.Color.textPrimary)
                            Text(user.phone).font(.caption).foregroundStyle(DS.Color.textSecondary)
                        }
                        Spacer()
                        foundUserAction(for: user)
                    }
                    if let hint = foundUserHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
                .listRowBackground(Color.appSurface)
            }
            ForEach(invitees, id: \.id) { invitee in
                HStack(spacing: 10) {
                    ProfileAvatarView(
                        displayName: invitee.displayName,
                        avatarUrl: invitee.avatarUrl,
                        userId: invitee.id,
                        size: 34,
                        fontSize: 13
                    )
                    Text(invitee.displayName).foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    Text(invitee.phone).font(.caption).foregroundStyle(DS.Color.textSecondary)
                }
                .listRowBackground(Color.appSurface)
            }
            .onDelete { indexSet in invitees.remove(atOffsets: indexSet) }
        } header: {
            Text("INVITE PEOPLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .textCase(nil)
        }
        .task { await loadContactsIfEnabled() }
        .onChange(of: settings.contactsEnabled) { _, _ in
            Task { await loadContactsIfEnabled() }
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func loadContactsIfEnabled() async {
        guard settings.contactsEnabled else {
            contactsManager.clear()
            contactSuggestions = []
            return
        }
        await contactsManager.load(requestsAccess: false)
        refreshContactSuggestions(for: inviteePhone)
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
                    .foregroundStyle(DS.Color.textSecondary)
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

    private func refreshContactSuggestions(for value: String) {
        guard settings.contactsEnabled else {
            contactSuggestions = []
            return
        }
        // Single pass with no write-back to inviteePhone, so typing causes one render per keystroke.
        let query: String
        if value.contains(where: { $0.isLetter }) {
            query = value
        } else {
            let raw = value.hasPrefix("+1") ? String(value.dropFirst(2)) : value
            query = raw.filter(\.isNumber)
        }
        contactSuggestions = query.isEmpty ? [] : Array(contactsManager.search(query).prefix(5))
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
                        .foregroundStyle(DS.Color.textSecondary)
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
            phone: friend.phoneE164 ?? "",
            avatarUrl: friend.avatarUrl
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

    private var shortName: String {
        let name = friend.displayName ?? "Unknown"
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return String(first.prefix(9))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack {
                    ProfileAvatarView(profile: friend, size: 44, fontSize: 16)
                    if isInvited {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                        Image(systemName: "checkmark")
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1)
                    }
                }
                Text(shortName)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(isInvited ? Color.coral : DS.Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isInvited ? "Remove \(shortName)" : "Invite \(shortName)")
    }
}
