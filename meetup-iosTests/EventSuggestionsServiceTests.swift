import Foundation
import Testing
@testable import meetup_ios

@Suite("EventSuggestionsService")
struct EventSuggestionsServiceTests {
    @Test("Ticketmaster URL requests relevant nearby current or future events")
    func ticketmasterURLIncludesGeoPointAndStartDateTime() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-10T20:00:00Z"))

        let url = TicketmasterEventSource.discoveryURL(
            apiKey: "test-key",
            latitude: 40.744,
            longitude: -74.032,
            radiusMiles: 25,
            now: now
        )

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(query["apikey"] == "test-key")
        #expect(query["geoPoint"] == TicketmasterEventSource.geoHash(latitude: 40.744, longitude: -74.032))
        #expect(query["latlong"] == nil)
        #expect(query["radius"] == "25")
        #expect(query["unit"] == "miles")
        #expect(query["sort"] == "relevance,desc")
        #expect(query["startDateTime"] == "2026-06-10T20:00:00Z")
    }

    @Test("Ticketmaster geoPoint uses standard geohash encoding")
    func ticketmasterGeoPointUsesGeohash() {
        #expect(TicketmasterEventSource.geoHash(latitude: 42.6, longitude: -5.6, precision: 5) == "ezs42")
    }

    @Test("Ticketmaster URL includes category preference")
    func ticketmasterURLIncludesClassificationName() throws {
        let url = TicketmasterEventSource.discoveryURL(
            apiKey: "test-key",
            latitude: 40.744,
            longitude: -74.032,
            radiusMiles: 10,
            classificationName: "Music"
        )

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(query["classificationName"] == "Music")
    }

    @Test("Event suggestions time out instead of loading forever")
    func eventFetchTimesOut() async throws {
        let service = EventSuggestionsService(source: HangingEventSource(), timeoutSeconds: 0.01)

        do {
            _ = try await service.nearbyEvents(latitude: 40.744, longitude: -74.032)
            Issue.record("Expected event suggestions to time out")
        } catch let error as EventSourceError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Expected EventSourceError.timedOut, got \(error)")
        }
    }

    @Test("Composite source merges healthy providers and ignores provider failures")
    func compositeSourceMergesHealthyProviders() async throws {
        let ticketmasterEvent = NearbyEvent(
            id: "tm-1",
            name: "Rooftop Set",
            startDate: nil,
            venueName: "Elsewhere",
            address: nil,
            coordinate: nil,
            url: nil
        )
        let cachedEvent = NearbyEvent(
            id: "cached-1",
            name: "Gallery Night",
            startDate: nil,
            venueName: "Chelsea",
            address: nil,
            coordinate: nil,
            url: nil
        )
        let source = CompositeEventSource(sources: [
            StaticEventSource(name: "Ticketmaster", events: [ticketmasterEvent]),
            FailingEventSource(),
            StaticEventSource(name: "Cached", events: [cachedEvent]),
        ])

        let events = try await source.fetchNearbyEvents(
            latitude: 40.744,
            longitude: -74.032,
            radiusMiles: 5,
            classificationName: nil
        )

        #expect(Set(events.map(\.id)) == Set(["tm-1", "cached-1"]))
    }

    @Test("Duplicate suggestions collapse to one card, keeping the soonest date")
    func dedupeCollapsesRepeatsAndRuns() throws {
        let mar1 = ISO8601DateFormatter().date(from: "2026-03-01T20:00:00Z")
        let mar2 = ISO8601DateFormatter().date(from: "2026-03-02T20:00:00Z")
        let mar3 = ISO8601DateFormatter().date(from: "2026-03-03T20:00:00Z")

        let events = [
            NearbyEvent(id: "A", name: "Hamilton", startDate: mar2, venueName: "Richard Rodgers", address: nil, coordinate: nil, url: nil),
            NearbyEvent(id: "A", name: "Hamilton", startDate: mar2, venueName: "Richard Rodgers", address: nil, coordinate: nil, url: nil), // exact ID repeat
            NearbyEvent(id: "B", name: "Hamilton", startDate: mar3, venueName: "Richard Rodgers", address: nil, coordinate: nil, url: nil), // same run, later night
            NearbyEvent(id: "C", name: "hamilton", startDate: mar1, venueName: "Richard Rodgers", address: nil, coordinate: nil, url: nil), // same run, earliest, different case
            NearbyEvent(id: "D", name: "Hamilton", startDate: mar2, venueName: "Other Theater", address: nil, coordinate: nil, url: nil),    // different venue → kept
        ]

        let deduped = EventSuggestionsService.dedupe(events)

        #expect(deduped.count == 2)
        let hamiltonAtRR = try #require(deduped.first { $0.venueName == "Richard Rodgers" })
        #expect(hamiltonAtRR.startDate == mar1) // soonest of the run is surfaced
        #expect(deduped.contains { $0.venueName == "Other Theater" })
    }
}

private struct HangingEventSource: EventSource {
    let sourceName = "Hanging"

    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent] {
        try await Task.sleep(for: .seconds(10))
        return []
    }
}

private struct StaticEventSource: EventSource {
    let sourceName: String
    let events: [NearbyEvent]

    init(name: String, events: [NearbyEvent]) {
        sourceName = name
        self.events = events
    }

    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent] {
        events
    }
}

private struct FailingEventSource: EventSource {
    let sourceName = "Failing"

    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusMiles: Int,
        classificationName: String?
    ) async throws -> [NearbyEvent] {
        throw EventSourceError.badResponse
    }
}
