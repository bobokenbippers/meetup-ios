import Foundation
import CoreLocation

// MARK: - Source abstraction

/// A swappable backing source for nearby real-world events. Implement this to add
/// a new provider (SeatGeek, a scrape, etc.) without touching the UI.
protocol EventSource: Sendable {
    var sourceName: String { get }
    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent]
}

enum EventSourceError: LocalizedError, Equatable {
    /// The provider key was never configured (placeholder still in Info.plist).
    case missingAPIKey
    case requestFailed(Int)
    case badResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:        return "Event suggestions are not configured."
        case .requestFailed(let c): return "Event source request failed (HTTP \(c))."
        case .badResponse:          return "Event source returned an unexpected response."
        case .timedOut:             return "Event source request timed out."
        }
    }
}

// MARK: - Service (singleton facade)

/// App-facing entry point for event suggestions. Holds the active `EventSource`
/// behind a clean call so the provider can be swapped in one place later.
final class EventSuggestionsService {
    static let shared = EventSuggestionsService()

    private let source: EventSource
    private let timeoutSeconds: Double

    init(source: EventSource = TicketmasterEventSource(), timeoutSeconds: Double = 8) {
        self.source = source
        self.timeoutSeconds = timeoutSeconds
    }

    var sourceName: String { source.sourceName }

    func nearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int = 25,
        classificationName: String? = nil
    ) async throws -> [NearbyEvent] {
        try await withThrowingTaskGroup(of: [NearbyEvent].self) { group in
            group.addTask { [self] in
                try await source.fetchNearbyEvents(
                    latitude: latitude,
                    longitude: longitude,
                    radiusMiles: radiusMiles,
                    classificationName: classificationName
                )
            }
            group.addTask { [self] in
                let milliseconds = max(1, Int(timeoutSeconds * 1_000))
                try await Task.sleep(for: .milliseconds(milliseconds))
                throw EventSourceError.timedOut
            }

            guard let result = try await group.next() else { throw EventSourceError.badResponse }
            group.cancelAll()
            cache(
                result,
                latitude: latitude,
                longitude: longitude,
                radiusMiles: radiusMiles,
                classificationName: classificationName
            )
            return result
        }
    }

    func cachedNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int = 25,
        classificationName: String? = nil
    ) -> [NearbyEvent]? {
        let key = Self.cacheKey(
            latitude: latitude,
            longitude: longitude,
            radiusMiles: radiusMiles,
            classificationName: classificationName
        )
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedEventSuggestions.self, from: data),
              Date().timeIntervalSince(cached.storedAt) < Self.cacheTTL
        else { return nil }
        return cached.events.map(\.nearbyEvent)
    }

    private func cache(
        _ events: [NearbyEvent],
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) {
        let key = Self.cacheKey(
            latitude: latitude,
            longitude: longitude,
            radiusMiles: radiusMiles,
            classificationName: classificationName
        )
        let cached = CachedEventSuggestions(
            storedAt: Date(),
            events: events.map(CachedNearbyEvent.init)
        )
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static let cacheTTL: TimeInterval = 30 * 60

    private static func cacheKey(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) -> String {
        let lat = (latitude * 100).rounded() / 100
        let lng = (longitude * 100).rounded() / 100
        let category = classificationName?.replacingOccurrences(of: " ", with: "-") ?? "all"
        return "eventSuggestions.\(lat).\(lng).\(radiusMiles).\(category)"
    }
}

// MARK: - Ticketmaster Discovery API

/// Ticketmaster-backed nearby event source. Search by lat/long + radius, no auth
/// header -- just an `apikey` query param. The Consumer Key is read from Info.plist
/// (`TicketmasterAPIKey`) and is never hardcoded in source.
struct TicketmasterEventSource: EventSource {
    let sourceName = "Ticketmaster"

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    private var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TicketmasterAPIKey") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              trimmed != "REPLACE_WITH_TICKETMASTER_CONSUMER_KEY" else { return nil }
        return trimmed
    }

    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent] {
        guard let apiKey else { throw EventSourceError.missingAPIKey }

        let url = Self.discoveryURL(
            apiKey: apiKey,
            latitude: latitude,
            longitude: longitude,
            radiusMiles: radiusMiles,
            classificationName: classificationName
        )

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw EventSourceError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw EventSourceError.requestFailed(http.statusCode) }

        let decoded = try JSONDecoder().decode(TMResponse.self, from: data)
        return (decoded.embedded?.events ?? []).compactMap(Self.map)
    }

    static func discoveryURL(
        apiKey: String,
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String? = nil,
        now: Date = Date()
    ) -> URL {
        var components = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        var queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "latlong", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "radius", value: String(radiusMiles)),
            URLQueryItem(name: "unit", value: "miles"),
            URLQueryItem(name: "size", value: "20"),
            URLQueryItem(name: "sort", value: "date,asc"),
            URLQueryItem(name: "startDateTime", value: ISO8601DateFormatter().string(from: now)),
        ]
        if let classificationName {
            queryItems.append(URLQueryItem(name: "classificationName", value: classificationName))
        }
        components.queryItems = queryItems
        return components.url!
    }

    // MARK: Mapping

    private static func map(_ event: TMEvent) -> NearbyEvent? {
        let venue = event.embedded?.venues?.first
        return NearbyEvent(
            id: event.id,
            name: event.name,
            startDate: parseStartDate(event.dates?.start),
            venueName: venue?.name,
            address: formatAddress(venue),
            coordinate: parseCoordinate(venue?.location),
            url: event.url
        )
    }

    private static func parseStartDate(_ start: TMStart?) -> Date? {
        guard let start else { return nil }
        if let dateTime = start.dateTime {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: dateTime) { return d }
        }
        guard let localDate = start.localDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        if let localTime = start.localTime {
            let timeStr = localTime.count == 5 ? localTime + ":00" : localTime
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = formatter.date(from: "\(localDate) \(timeStr)") { return d }
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: localDate)
    }

    private static func parseCoordinate(_ location: TMLocation?) -> CLLocationCoordinate2D? {
        guard let location,
              let latStr = location.latitude, let lat = Double(latStr),
              let lngStr = location.longitude, let lng = Double(lngStr) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func formatAddress(_ venue: TMVenue?) -> String? {
        guard let venue else { return nil }
        let parts = [
            venue.address?.line1,
            venue.city?.name,
            venue.state?.stateCode,
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Ticketmaster JSON DTOs
// Map only the fields we use; the API payload is large and mostly irrelevant here.

private struct TMResponse: Decodable {
    let embedded: TMEmbedded?
    enum CodingKeys: String, CodingKey { case embedded = "_embedded" }
}

private struct TMEmbedded: Decodable {
    let events: [TMEvent]?
}

private struct TMEvent: Decodable {
    let id: String
    let name: String
    let url: String?
    let dates: TMDates?
    let embedded: TMEventEmbedded?
    enum CodingKeys: String, CodingKey {
        case id, name, url, dates
        case embedded = "_embedded"
    }
}

private struct TMDates: Decodable {
    let start: TMStart?
}

private struct TMStart: Decodable {
    let localDate: String?
    let localTime: String?
    let dateTime: String?
}

private struct TMEventEmbedded: Decodable {
    let venues: [TMVenue]?
}

private struct TMVenue: Decodable {
    let name: String?
    let address: TMAddress?
    let city: TMCity?
    let state: TMState?
    let location: TMLocation?
}

private struct TMAddress: Decodable { let line1: String? }
private struct TMCity: Decodable { let name: String? }
private struct TMState: Decodable { let stateCode: String? }
private struct TMLocation: Decodable { let latitude: String?; let longitude: String? }

private struct CachedEventSuggestions: Codable {
    let storedAt: Date
    let events: [CachedNearbyEvent]
}

private struct CachedNearbyEvent: Codable {
    let id: String
    let name: String
    let startDate: Date?
    let venueName: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let url: String?

    init(_ event: NearbyEvent) {
        id = event.id
        name = event.name
        startDate = event.startDate
        venueName = event.venueName
        address = event.address
        latitude = event.coordinate?.latitude
        longitude = event.coordinate?.longitude
        url = event.url
    }

    var nearbyEvent: NearbyEvent {
        let coordinate: CLLocationCoordinate2D?
        if let latitude, let longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }
        return NearbyEvent(
            id: id,
            name: name,
            startDate: startDate,
            venueName: venueName,
            address: address,
            coordinate: coordinate,
            url: url
        )
    }
}
