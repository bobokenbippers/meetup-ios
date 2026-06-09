import SwiftUI
import CoreLocation

/// Host-only sheet to change an existing meetup's destination.
/// Re-selecting a place via Google Places carries name + address + coordinates together,
/// so the map pin and directions stay consistent — matching the creation flow.
struct EditMeetupLocationView: View {
    let meetup: Meetup
    let onUpdated: (Meetup) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlace: SelectedPlace?
    @State private var isSaving = false
    @State private var error: String?

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

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit Location")
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
                                Text("Save Location")
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
                            .accessibilityIdentifier("btn_save_location")
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

    private func save() async {
        guard let place = selectedPlace else { return }
        isSaving = true
        error = nil
        do {
            let updated = try await MeetupService.shared.updateDestination(
                meetupId: meetup.id,
                destinationName: place.name,
                destinationAddress: place.address,
                lat: place.coordinate.latitude,
                lng: place.coordinate.longitude
            )
            onUpdated(updated)
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
