import SwiftUI
import CoreLocation

/// "Happening near you" — a horizontally-scrolling row of real events near the
/// user's current location. Tapping a card opens the create-meetup flow pre-filled
/// with that event's title, date/time, and venue. Renders nothing (quietly) when
/// there's no location permission, no key configured, or no events nearby.
struct NearbyEventsView: View {
    /// Hand a pre-fill back up so the parent can present `CreateMeetupView`.
    let onSelect: (EventPrefill) -> Void

    @State private var events: [NearbyEvent] = []
    @State private var phase: Phase = .idle

    private var locationManager: LocationManager { .shared }

    private enum Phase { case idle, loading, loaded, hidden }

    // Changing this re-runs the load: "none" until a fix arrives, then the coordinate.
    private var locationKey: String {
        guard let l = locationManager.location else { return "none" }
        return String(format: "%.3f,%.3f", l.coordinate.latitude, l.coordinate.longitude)
    }

    var body: some View {
        Group {
            switch phase {
            case .loaded where !events.isEmpty:
                content
            case .loading:
                loadingRow
            default:
                EmptyView()
            }
        }
        .task { locationManager.requestOneShotLocation() }
        .task(id: locationKey) { await load() }
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

    // MARK: - Data

    private func load() async {
        guard let location = locationManager.location else {
            // No fix yet — stay idle; the location-keyed task re-runs once one arrives.
            if phase != .loaded { phase = .idle }
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
            phase = actionable.isEmpty ? .hidden : .loaded
        } catch is CancellationError {
            return
        } catch {
            // Missing key / network / decode — fail silently and hide the section.
            phase = .hidden
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
