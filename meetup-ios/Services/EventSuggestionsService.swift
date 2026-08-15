import Foundation
import CoreLocation
import Supabase

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

    init(
        source: EventSource = CompositeEventSource(sources: [
            TicketmasterEventSource(),
            SupabaseCachedEventSource(),
        ]),
        timeoutSeconds: Double = 8
    ) {
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
            let deduped = Self.dedupe(result)
            cache(
                deduped,
                latitude: latitude,
                longitude: longitude,
                radiusMiles: radiusMiles,
                classificationName: classificationName
            )
            return deduped
        }
    }

    /// Collapse duplicate suggestions before they reach the UI (and the cache).
    ///
    /// Providers like Ticketmaster return the same logical event more than once —
    /// most often a multi-night run listed as one entry per performance date, and
    /// occasionally the exact same event ID twice. `ForEach` over those produced
    /// visibly stacked, near-identical cards. We drop exact ID repeats, then collapse
    /// entries sharing a name + venue down to a single card, keeping the soonest date.
    static func dedupe(_ events: [NearbyEvent]) -> [NearbyEvent] {
        var seenIDs = Set<String>()
        var indexByLogicalKey: [String: Int] = [:]
        var output: [NearbyEvent] = []

        for event in events {
            guard seenIDs.insert(event.id).inserted else { continue }

            let key = logicalKey(for: event)
            if let existingIndex = indexByLogicalKey[key] {
                if isEarlier(event.startDate, than: output[existingIndex].startDate) {
                    output[existingIndex] = event
                }
            } else {
                indexByLogicalKey[key] = output.count
                output.append(event)
            }
        }
        return output
    }

    private static func logicalKey(for event: NearbyEvent) -> String {
        let name = event.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let venue = (event.venueName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name)|\(venue)"
    }

    private static func isEarlier(_ lhs: Date?, than rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l < r
        case (_?, nil):    return true   // a dated event wins over an undated one
        case (nil, _):     return false
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

// MARK: - Composite source

/// Merges official live search with the server-side cached feed. Individual
/// provider failures are non-fatal as long as another provider returns events.
struct CompositeEventSource: EventSource {
    let sourceName: String
    private let sources: [any EventSource]

    init(sources: [any EventSource]) {
        self.sources = sources
        sourceName = sources.map { $0.sourceName }.joined(separator: " + ")
    }

    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent] {
        try await withThrowingTaskGroup(of: [NearbyEvent].self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return try await source.fetchNearbyEvents(
                            latitude: latitude,
                            longitude: longitude,
                            radiusMiles: radiusMiles,
                            classificationName: classificationName
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return []
                    }
                }
            }

            var merged: [NearbyEvent] = []

            for try await events in group {
                merged.append(contentsOf: events)
            }

            return merged
        }
    }
}

// MARK: - Supabase cached events

/// Reads normalized events populated by the scheduled backend ingest job. This
/// source is intentionally read-only in the app; ingestion uses service-role
/// credentials outside the client.
struct SupabaseCachedEventSource: EventSource {
    let sourceName = "Cached events"
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent] {
        struct Params: Encodable {
            let p_lat: Double
            let p_lng: Double
            let p_radius_miles: Int
            let p_category: String?
            let p_limit: Int
        }

        let rows: [CachedEventRow] = try await supabase
            .rpc("search_cached_events", params: Params(
                p_lat: latitude,
                p_lng: longitude,
                p_radius_miles: radiusMiles,
                p_category: classificationName,
                p_limit: 20
            ))
            .execute()
            .value

        return rows.map(\.nearbyEvent)
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
            URLQueryItem(name: "geoPoint", value: geoHash(latitude: latitude, longitude: longitude)),
            URLQueryItem(name: "radius", value: String(radiusMiles)),
            URLQueryItem(name: "unit", value: "miles"),
            URLQueryItem(name: "size", value: "20"),
            URLQueryItem(name: "sort", value: "relevance,desc"),
            URLQueryItem(name: "startDateTime", value: ISO8601DateFormatter().string(from: now)),
        ]
        if let classificationName {
            queryItems.append(URLQueryItem(name: "classificationName", value: classificationName))
        }
        components.queryItems = queryItems
        return components.url!
    }

    static func geoHash(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latitudeRange = (-90.0, 90.0)
        var longitudeRange = (-180.0, 180.0)
        var isLongitudeBit = true
        var bit = 0
        var characterIndex = 0
        var output = ""

        while output.count < precision {
            if isLongitudeBit {
                let midpoint = (longitudeRange.0 + longitudeRange.1) / 2
                if longitude >= midpoint {
                    characterIndex = (characterIndex << 1) + 1
                    longitudeRange.0 = midpoint
                } else {
                    characterIndex <<= 1
                    longitudeRange.1 = midpoint
                }
            } else {
                let midpoint = (latitudeRange.0 + latitudeRange.1) / 2
                if latitude >= midpoint {
                    characterIndex = (characterIndex << 1) + 1
                    latitudeRange.0 = midpoint
                } else {
                    characterIndex <<= 1
                    latitudeRange.1 = midpoint
                }
            }

            isLongitudeBit.toggle()
            bit += 1

            if bit == 5 {
                output.append(base32[characterIndex])
                bit = 0
                characterIndex = 0
            }
        }

        return output
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
private struct TMLocation: Decodable {
    let latitude: String?
    let longitude: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = Self.decodeCoordinateString(.latitude, from: container)
        longitude = Self.decodeCoordinateString(.longitude, from: container)
    }

    private static func decodeCoordinateString(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String? {
        if let string = try? container.decode(String.self, forKey: key) {
            return string
        }
        if let double = try? container.decode(Double.self, forKey: key) {
            return String(double)
        }
        return nil
    }
}

private struct CachedEventRow: Decodable {
    let sourceName: String
    let sourceEventId: String
    let title: String
    let venueName: String?
    let address: String?
    let lat: Double
    let lng: Double
    let startsAt: Date?
    let sourceUrl: String

    enum CodingKeys: String, CodingKey {
        case sourceName = "source_name"
        case sourceEventId = "source_event_id"
        case title
        case venueName = "venue_name"
        case address
        case lat
        case lng
        case startsAt = "starts_at"
        case sourceUrl = "source_url"
    }

    var nearbyEvent: NearbyEvent {
        NearbyEvent(
            id: "\(sourceName):\(sourceEventId)",
            name: title,
            startDate: startsAt,
            venueName: venueName,
            address: address,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            url: sourceUrl
        )
    }
}

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
