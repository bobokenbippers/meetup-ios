import CoreLocation

/// A real-world event surfaced from a third-party events source (e.g. Ticketmaster),
/// normalized into the shape the app needs to render a suggestion card and pre-fill
/// the create-meetup flow. This is intentionally source-agnostic — the backing
/// `EventSource` maps its own JSON into this type.
struct NearbyEvent: Identifiable, Sendable {
    let id: String
    let name: String
    let startDate: Date?
    let venueName: String?
    let address: String?
    let coordinate: CLLocationCoordinate2D?
    let url: String?

    /// Straight-line distance in miles from the user's location, if both points exist.
    func distanceMiles(from userLocation: CLLocation?) -> Double? {
        guard let userLocation, let coordinate else { return nil }
        let venue = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userLocation.distance(from: venue) / 1609.344
    }
}

/// Everything the create-meetup flow needs to open pre-filled from a tapped event:
/// the event title (used as the meetup category), its date/time (target arrival),
/// and the venue as a `SelectedPlace` (destination name/address/coordinate).
struct EventPrefill {
    let title: String
    let date: Date?
    let place: SelectedPlace
}
