import Foundation
import CoreLocation
import GooglePlacesSwift

struct GooglePlacePrediction: Identifiable {
    let placeId: String
    let mainText: String
    let secondaryText: String
    // Session token is carried forward so autocomplete + details are billed as one session.
    let sessionToken: AutocompleteSessionToken
    var id: String { placeId }
}

@MainActor
final class GooglePlacesService {
    static let shared = GooglePlacesService()

    private let client = PlacesClient.shared
    private var sessionToken = AutocompleteSessionToken()

    private init() {}

    func autocomplete(query: String) async -> [GooglePlacePrediction] {
        let request = AutocompleteRequest(query: query, sessionToken: sessionToken)
        switch await client.fetchAutocompleteSuggestions(with: request) {
        case .success(let suggestions):
            return suggestions.compactMap { suggestion in
                guard case .place(let place) = suggestion else { return nil }
                return GooglePlacePrediction(
                    placeId: place.placeID,
                    mainText: place.legacyAttributedPrimaryText.string,
                    secondaryText: place.legacyAttributedSecondaryText?.string ?? "",
                    sessionToken: sessionToken
                )
            }
        case .failure:
            return []
        }
    }

    func details(for prediction: GooglePlacePrediction) async -> SelectedPlace? {
        let request = FetchPlaceRequest(
            placeID: prediction.placeId,
            placeProperties: [.displayName, .formattedAddress, .coordinate],
            sessionToken: prediction.sessionToken
        )
        // Rotate token after a completed session (autocomplete → details pair).
        sessionToken = AutocompleteSessionToken()
        switch await client.fetchPlace(with: request) {
        case .success(let place):
            return SelectedPlace(
                name: place.displayName ?? prediction.mainText,
                address: place.formattedAddress,
                coordinate: place.location
            )
        case .failure:
            return nil
        }
    }
}
