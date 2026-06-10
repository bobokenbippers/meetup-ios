import SwiftUI
import CoreLocation
import UIKit

/// "Happening near you" — a horizontally-scrolling row of real events near the
/// user's current location. Tapping a card opens the create-meetup flow pre-filled
/// with that event's title, date/time, and venue.
struct NearbyEventsView: View {
    /// Hand a pre-fill back up so the parent can present `CreateMeetupView`.
    let onSelect: (EventPrefill) -> Void

    @Environment(\.openURL) private var openURL
    @State private var events: [NearbyEvent] = []
    @State private var phase: Phase = .idle

    private var locationManager: LocationManager { .shared }

    private enum Phase {
        case idle
        case loading
        case loaded
        case needsLocation
        case empty
        case failed(String)
    }

    // Changing this re-runs the load: "none" until a fix arrives, then the coordinate.
    private var locationKey: String {
        guard let l = locationManager.location else { return "none" }
        return String(format: "%.3f,%.3f", l.coordinate.latitude, l.coordinate.longitude)
    }

    private var loadKey: String {
        "\(locationManager.authorizationStatus.rawValue)|\(locationKey)"
    }

    var body: some View {
        Group {
            switch phase {
            case .loaded where !events.isEmpty:
                content
            case .loading:
                loadingRow
            case .needsLocation:
                locationPromptRow
            case .empty:
                emptyRow
            case .failed(let message):
                failedRow(message: message)
            default:
                EmptyView()
            }
        }
        .task(id: loadKey) { await load() }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(events) { event in
                        Button {
                            if let prefill = prefill(for: event) { onSelect(prefill) }
                        } label: {
                            NearbyEventCard(
                                event: event,
                                distanceMiles: event.distanceMiles(from: locationManager.location)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Plan a meetup at \(event.name)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("✨")
                .scaledFont(size: 12)
            Text("HAPPENING NEAR YOU")
                .scaledFont(size: 10, weight: .bold)
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(.leading, 16)
    }

    private var loadingRow: some View {
        HStack {
            ProgressView()
                .tint(Color.coral)
            Text("Finding events near you…")
                .scaledFont(size: 12)
                .foregroundStyle(Color(white: 0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var locationPromptRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                Image(systemName: "location")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.coral)
                    .frame(width: 28, height: 28)
                    .background(Color.coral.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on location for local events")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                    Text("We'll show ideas near you.")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color(white: 0.58))
                }

                Spacer(minLength: 8)

                Button(action: requestLocation) {
                    Text(locationButtonTitle)
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.coral)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }

    private var locationButtonTitle: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "Enable"
        case .authorizedWhenInUse, .authorizedAlways:
            return "Retry"
        case .denied, .restricted:
            return "Settings"
        @unknown default:
            return "Settings"
        }
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text("No nearby events right now")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Color(white: 0.58))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .padding(.vertical, 6)
    }

    private func failedRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.coral)
                    .frame(width: 28, height: 28)
                    .background(Color.coral.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Events didn't load")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(message)
                        .scaledFont(size: 11)
                        .foregroundStyle(Color(white: 0.58))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await load() }
                } label: {
                    Text("Retry")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.coral)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Data

    private func load() async {
        guard let location = locationManager.location else {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                phase = .needsLocation
            case .authorizedWhenInUse, .authorizedAlways:
                phase = .loading
                locationManager.requestOneShotLocation()
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled, locationManager.location == nil {
                    phase = .needsLocation
                }
            case .denied, .restricted:
                phase = .needsLocation
            @unknown default:
                phase = .needsLocation
            }
            return
        }
        phase = .loading
        do {
            let result = try await EventSuggestionsService.shared.nearbyEvents(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            // Only events with a coordinate are actionable (the create flow needs lat/lng).
            let actionable = result.filter { $0.coordinate != nil }
            events = actionable
            phase = actionable.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(Self.eventLoadMessage(for: error))
        }
    }

    private static func eventLoadMessage(for error: Error) -> String {
        if let sourceError = error as? EventSourceError {
            switch sourceError {
            case .missingAPIKey:
                return "Event suggestions are temporarily unavailable."
            case .requestFailed, .badResponse:
                return "Check your connection and try again."
            }
        }
        return "Check your connection and try again."
    }

    private func requestLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestOneShotLocation()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestOneShotLocation()
        @unknown default:
            break
        }
    }

    private func prefill(for event: NearbyEvent) -> EventPrefill? {
        guard let coordinate = event.coordinate else { return nil }
        let place = SelectedPlace(
            name: event.venueName ?? event.name,
            address: event.address,
            coordinate: coordinate
        )
        return EventPrefill(
            title: event.name,
            date: event.startDate.map(Self.roundToQuarterHour),
            place: place
        )
    }

    // Create-meetup's time wheel snaps to 15-minute marks, so align the pre-fill to match.
    private static func roundToQuarterHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let rounded = Int((Double(minute) / 15.0).rounded()) * 15
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        comps.minute = rounded % 60
        if rounded == 60 { comps.hour = (comps.hour ?? 0) + 1 }
        comps.second = 0
        return calendar.date(from: comps) ?? date
    }
}

// MARK: - Card

private struct NearbyEventCard: View {
    let event: NearbyEvent
    let distanceMiles: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.name)
                .scaledFont(size: 14, weight: .bold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let date = event.startDate {
                Label {
                    Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .scaledFont(size: 11, weight: .medium)
                } icon: {
                    Image(systemName: "calendar")
                        .scaledFont(size: 10)
                }
                .foregroundStyle(Color.coral)
                .lineLimit(1)
            }

            if let venue = event.venueName {
                Label {
                    Text(venue)
                        .scaledFont(size: 11)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .scaledFont(size: 10)
                }
                .foregroundStyle(Color(white: 0.6))
            }

            if let miles = distanceMiles {
                Text(String(format: "%.1f mi away", miles))
                    .scaledFont(size: 10, weight: .medium)
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(14)
        .frame(width: 200, height: 130, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.appSurface)
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.coral.opacity(0.25), lineWidth: 1)
        }
    }
}
