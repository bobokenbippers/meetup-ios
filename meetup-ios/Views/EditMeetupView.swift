import SwiftUI
import CoreLocation

/// Host-only sheet to change an existing meetup's destination and/or scheduled time.
/// Re-selecting a place carries name + address + coordinates together,
/// so the map pin and directions stay consistent — matching the creation flow. Editing the
/// time writes target_arrival_at, which the cron push/expiry functions read live.
struct EditMeetupView: View {
    let meetup: Meetup
    let onUpdated: (Meetup) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlace: SelectedPlace?
    @State private var selectedTime: Date
    @State private var timeIsDirty = false
    @State private var isSaving = false
    @State private var error: String?

    init(meetup: Meetup, onUpdated: @escaping (Meetup) -> Void) {
        self.meetup = meetup
        self.onUpdated = onUpdated
        // Seed the picker with the current time, or the next hour if none was set yet.
        let seed = meetup.targetArrivalAt ?? Date().addingTimeInterval(3600)
        _selectedTime = State(initialValue: seed)
    }

    private var hasChanges: Bool { selectedPlace != nil || timeIsDirty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    currentDestinationRow
                } header: {
                    Text("CURRENT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                EditDestinationSection(selectedPlace: $selectedPlace)

                timeSection

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit Meetup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider().overlay(Color(white: 0.15))
                    Group {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            Button {
                                Task { await save() }
                            } label: {
                                Text("Save Changes")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(hasChanges ? Color.coral : Color.coral.opacity(0.45))
                                    )
                            }
                            .disabled(!hasChanges)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .accessibilityIdentifier("btn_save_meetup")
                        }
                    }
                    .background(Color.appBackground)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var currentDestinationRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.coral)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(meetup.destinationName)
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                if let addr = meetup.destinationAddress {
                    Text(addr)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.6))
                }
            }
            Spacer()
        }
        .listRowBackground(Color.appSurface)
    }

    private var timeSection: some View {
        Section {
            DatePicker(
                "Arrival time",
                selection: $selectedTime,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .foregroundStyle(.white)
            .tint(Color.coral)
            .listRowBackground(Color.appSurface)
            .accessibilityIdentifier("picker_target_arrival")
            .onChange(of: selectedTime) { _, _ in timeIsDirty = true }
        } header: {
            Text("TARGET ARRIVAL TIME")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.4))
                .textCase(nil)
        } footer: {
            if meetup.targetArrivalAt == nil {
                Text("No time set yet — pick one to schedule the meetup.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.5))
            }
        }
    }

    private func save() async {
        guard hasChanges else { return }
        isSaving = true
        error = nil
        do {
            var latest = meetup
            if let place = selectedPlace {
                latest = try await MeetupService.shared.updateDestination(
                    meetupId: meetup.id,
                    destinationName: place.name,
                    destinationAddress: place.address,
                    lat: place.coordinate.latitude,
                    lng: place.coordinate.longitude
                )
            }
            if timeIsDirty {
                latest = try await MeetupService.shared.updateTargetArrival(
                    meetupId: meetup.id,
                    targetArrivalAt: selectedTime
                )
            }
            onUpdated(latest)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Destination Section
// Owns its own searchQuery/predictions so typing here never re-renders the parent.
// Mirrors CreateMeetupView's DestinationSection.

private struct EditDestinationSection: View {
    @Binding var selectedPlace: SelectedPlace?
    @State private var searchQuery = ""
    @State private var predictions: [PlaceSearchResult] = []
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
                TextField("Search for a new place", text: $searchQuery)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .tint(Color.coral)
                    .accessibilityIdentifier("field_new_destination")
                    .listRowBackground(Color.appSurface)
                if isLoadingDetails {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowBackground(Color.appSurface)
                }
                ForEach(predictions) { prediction in
                    Button(action: { selectPrediction(prediction) }) {
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
            Text("NEW DESTINATION")
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

    private func selectPrediction(_ prediction: PlaceSearchResult) {
        predictions = []
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
    }
}
