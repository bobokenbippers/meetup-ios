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

    private var sessionToken = AutocompleteSessionToken()
    private var hasProvidedAPIKey = false

    private init() {}

    var isConfigured: Bool {
        validAPIKey != nil
    }

    var unavailableMessage: String {
        "Location search is temporarily unavailable."
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
        guard let client = configuredClient() else { return [] }
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
        guard let client = configuredClient() else { return nil }
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
