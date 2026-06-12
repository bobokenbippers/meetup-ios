import Foundation
import Testing
@testable import meetup_ios

@Suite("EventSuggestionsService")
struct EventSuggestionsServiceTests {
    @Test("Ticketmaster URL requests only current or future events")
    func ticketmasterURLIncludesStartDateTime() throws {
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
        #expect(query["latlong"] == "40.744,-74.032")
        #expect(query["radius"] == "25")
        #expect(query["unit"] == "miles")
        #expect(query["sort"] == "date,asc")
        #expect(query["startDateTime"] == "2026-06-10T20:00:00Z")
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
