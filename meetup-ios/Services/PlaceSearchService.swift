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

    var unavailableMessage: String {
        "No places found. Try a more specific search."
    }

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
              !Task.isCancelled else {
            return await geocodeFallback(query: trimmed, near: location)
        }

        let mapResults: [PlaceSearchResult] = response.mapItems.prefix(8).enumerated().compactMap {
            offset, item -> PlaceSearchResult? in
            guard let place = SelectedPlace(mapItem: item) else { return nil }
            let coordinate = item.location.coordinate
            return PlaceSearchResult(
                id: "\(coordinate.latitude),\(coordinate.longitude)-\(offset)",
                mainText: place.name,
                secondaryText: place.address ?? "",
                place: place
            )
        }
        guard mapResults.isEmpty else { return mapResults }
        return await geocodeFallback(query: trimmed, near: location)
    }

    private func geocodeFallback(query: String, near location: CLLocation?) async -> [PlaceSearchResult] {
        let region: CLRegion? = location.map {
            CLCircularRegion(center: $0.coordinate, radius: 50_000, identifier: "destination-search")
        }
        guard let placemarks = try? await CLGeocoder().geocodeAddressString(query, in: region),
              !Task.isCancelled else { return [] }

        return placemarks.prefix(5).enumerated().compactMap { offset, placemark in
            guard let place = SelectedPlace(placemark: placemark, fallbackName: query) else { return nil }
            return PlaceSearchResult(
                id: "geocode-\(place.coordinate.latitude),\(place.coordinate.longitude)-\(offset)",
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
            address: mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: false),
            coordinate: mapItem.location.coordinate
        )
    }

    init?(placemark: CLPlacemark, fallbackName: String) {
        guard let coordinate = placemark.location?.coordinate else { return nil }
        let name = [placemark.name, placemark.thoroughfare, placemark.locality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallbackName

        self.init(
            name: name,
            address: placemark.formattedAddress(excluding: name),
            coordinate: coordinate
        )
    }
}

private extension CLPlacemark {
    func formattedAddress(excluding name: String) -> String? {
        let cityStateZip = [locality, administrativeArea, postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let parts = [thoroughfare, cityStateZip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != name }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
