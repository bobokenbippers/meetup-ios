import Foundation
import CoreLocation
import MapKit

struct PlaceSearchResult: Identifiable {
    let id: String
    let mainText: String
    let secondaryText: String
    let place: SelectedPlace
}

@MainActor
final class PlaceSearchService {
    static let shared = PlaceSearchService()

    private init() {}

    func search(query: String, near location: CLLocation?) async -> [PlaceSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }

        guard let response = try? await MKLocalSearch(request: request).start(),
              !Task.isCancelled else { return [] }

        return response.mapItems.prefix(5).enumerated().compactMap { offset, item in
            guard let place = SelectedPlace(mapItem: item) else { return nil }
            return PlaceSearchResult(
                id: "\(item.placemark.coordinate.latitude),\(item.placemark.coordinate.longitude)-\(offset)",
                mainText: place.name,
                secondaryText: place.address ?? "",
                place: place
            )
        }
    }
}

private extension SelectedPlace {
    init?(mapItem: MKMapItem) {
        guard let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }

        self.init(
            name: name,
            address: mapItem.placemark.formattedAddress,
            coordinate: mapItem.placemark.coordinate
        )
    }
}

private extension MKPlacemark {
    var formattedAddress: String? {
        let cityStateZip = [locality, administrativeArea, postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let parts = [thoroughfare, cityStateZip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
