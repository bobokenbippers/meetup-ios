import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum EventSuggestionCategoryPreference: String, CaseIterable, Identifiable {
    case all
    case music
    case sports
    case artsTheater
    case family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Events"
        case .music: return "Music"
        case .sports: return "Sports"
        case .artsTheater: return "Arts & Theater"
        case .family: return "Family"
        }
    }

    var ticketmasterClassificationName: String? {
        switch self {
        case .all: return nil
        case .music: return "Music"
        case .sports: return "Sports"
        case .artsTheater: return "Arts & Theatre"
        case .family: return "Family"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    var themePreference: ThemePreference {
        didSet { UserDefaults.standard.set(themePreference.rawValue, forKey: "themePreference") }
    }
    var boldText: Bool {
        didSet { UserDefaults.standard.set(boldText, forKey: "boldText") }
    }
    var largerText: Bool {
        didSet { UserDefaults.standard.set(largerText, forKey: "largerText") }
    }
    var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion") }
    }
    var contactsEnabled: Bool {
        didSet { UserDefaults.standard.set(contactsEnabled, forKey: "contactsEnabled") }
    }
    var eventSuggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(eventSuggestionsEnabled, forKey: "eventSuggestionsEnabled") }
    }
    var eventSuggestionRadiusMiles: Int {
        didSet { UserDefaults.standard.set(eventSuggestionRadiusMiles, forKey: "eventSuggestionRadiusMiles") }
    }
    var eventSuggestionCategory: EventSuggestionCategoryPreference {
        didSet { UserDefaults.standard.set(eventSuggestionCategory.rawValue, forKey: "eventSuggestionCategory") }
    }

    var colorScheme: ColorScheme? {
        switch themePreference {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    var eventSuggestionClassificationName: String? {
        eventSuggestionCategory.ticketmasterClassificationName
    }

    init() {
        let d = UserDefaults.standard
        let rawTheme = d.string(forKey: "themePreference") ?? ""
        themePreference = ThemePreference(rawValue: rawTheme) ?? .system
        boldText = d.bool(forKey: "boldText")
        largerText = d.bool(forKey: "largerText")
        reduceMotion = d.bool(forKey: "reduceMotion")
        contactsEnabled = d.bool(forKey: "contactsEnabled")
        eventSuggestionsEnabled = d.object(forKey: "eventSuggestionsEnabled") == nil
            ? true
            : d.bool(forKey: "eventSuggestionsEnabled")
        let storedRadius = d.integer(forKey: "eventSuggestionRadiusMiles")
        eventSuggestionRadiusMiles = storedRadius == 0 ? 25 : storedRadius
        let rawCategory = d.string(forKey: "eventSuggestionCategory") ?? ""
        eventSuggestionCategory = EventSuggestionCategoryPreference(rawValue: rawCategory) ?? .all
    }
}
