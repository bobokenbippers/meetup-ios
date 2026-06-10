import Foundation
import CoreLocation
import GooglePlacesSwift
import MapKit

struct GooglePlacePrediction: Identifiable {
    let mainText: String
    let secondaryText: String
    let source: GooglePlacePredictionSource

    var id: String {
        switch source {
        case .google(let placeId, _):
            return "google-\(placeId)"
        case .mapKit(let place):
            return "mapkit-\(place.name)-\(place.coordinate.latitude)-\(place.coordinate.longitude)"
        }
    }
}

enum GooglePlacePredictionSource {
    case google(placeId: String, sessionToken: AutocompleteSessionToken)
    case mapKit(SelectedPlace)
}

@MainActor
final class GooglePlacesService {
    static let shared = GooglePlacesService()

    private var sessionToken = AutocompleteSessionToken()
    private var hasProvidedAPIKey = false

    private init() {}

    var isConfigured: Bool {
        true
    }

    var unavailableMessage: String {
        "No places found. Try a more specific search."
    }

    @discardableResult
    func configureIfPossible() -> Bool {
        guard let apiKey = validAPIKey else { return false }
        guard !hasProvidedAPIKey else { return true }
        guard PlacesClient.provideAPIKey(apiKey) else { return false }
        hasProvidedAPIKey = true
        return true
    }

    func autocomplete(query: String) async -> [GooglePlacePrediction] {
        let googleResults = await googleAutocomplete(query: query)
        if !googleResults.isEmpty { return googleResults }
        return await mapKitAutocomplete(query: query)
    }

    private func googleAutocomplete(query: String) async -> [GooglePlacePrediction] {
        guard let client = configuredClient() else { return [] }
        let request = AutocompleteRequest(query: query, sessionToken: sessionToken)
        switch await client.fetchAutocompleteSuggestions(with: request) {
        case .success(let suggestions):
            return suggestions.compactMap { suggestion in
                guard case .place(let place) = suggestion else { return nil }
                return GooglePlacePrediction(
                    mainText: place.legacyAttributedPrimaryText.string,
                    secondaryText: place.legacyAttributedSecondaryText?.string ?? "",
                    source: .google(placeId: place.placeID, sessionToken: sessionToken)
                )
            }
        case .failure:
            return []
        }
    }

    func details(for prediction: GooglePlacePrediction) async -> SelectedPlace? {
        switch prediction.source {
        case .google(let placeId, let token):
            return await googleDetails(
                placeId: placeId,
                token: token,
                fallbackName: prediction.mainText
            )
        case .mapKit(let place):
            return place
        }
    }

    private func googleDetails(
        placeId: String,
        token: AutocompleteSessionToken,
        fallbackName: String
    ) async -> SelectedPlace? {
        guard let client = configuredClient() else { return nil }
        let request = FetchPlaceRequest(
            placeID: placeId,
            placeProperties: [.displayName, .formattedAddress, .coordinate],
            sessionToken: token
        )
        // Rotate token after a completed session (autocomplete → details pair).
        self.sessionToken = AutocompleteSessionToken()
        switch await client.fetchPlace(with: request) {
        case .success(let place):
            return SelectedPlace(
                name: place.displayName ?? fallbackName,
                address: place.formattedAddress,
                coordinate: place.location
            )
        case .failure:
            return nil
        }
    }

    private func mapKitAutocomplete(query: String) async -> [GooglePlacePrediction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(8).compactMap { item in
                let name = item.name ?? item.placemark.title ?? trimmed
                let address = formattedAddress(for: item)
                let place = SelectedPlace(
                    name: name,
                    address: address,
                    coordinate: item.placemark.coordinate
                )
                return GooglePlacePrediction(
                    mainText: name,
                    secondaryText: address ?? "",
                    source: .mapKit(place)
                )
            }
        } catch {
            return []
        }
    }

    private func formattedAddress(for item: MKMapItem) -> String? {
        let placemark = item.placemark
        let itemName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { part in
            guard !part.isEmpty else { return false }
            return itemName.map { $0 != part } ?? true
        }

        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        let title = placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title != itemName else { return nil }
        return title
    }

    private var validAPIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "REPLACE_WITH_GOOGLE_PLACES_API_KEY",
              !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private func configuredClient() -> PlacesClient? {
        guard configureIfPossible() else { return nil }
        return PlacesClient.shared
    }
}
