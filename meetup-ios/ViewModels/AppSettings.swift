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

enum AppColorTheme: String, CaseIterable, Identifiable {
    case standard
    case knicks

    var id: String { rawValue }

    static var current: AppColorTheme {
        let rawTheme = UserDefaults.standard.string(forKey: "appColorTheme") ?? ""
        return AppColorTheme(rawValue: rawTheme) ?? .standard
    }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .knicks: return "Knicks"
        }
    }

    var accentColor: Color {
        switch self {
        case .standard:
            return Color(light: Color(hex: "6C57C5"), dark: Color(hex: "8A78E0"))
        case .knicks:
            return Color(light: Color(hex: "006BB6"), dark: Color(hex: "3BA3FF"))
        }
    }

    var accentForegroundColor: Color {
        switch self {
        case .standard, .knicks:
            return Color(light: .white, dark: .black)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .standard:
            return Color(light: Color(hex: "6C57C5"), dark: Color(hex: "8A78E0"))
        case .knicks:
            // Official Knicks Orange #F58426; lightened for dark-mode contrast.
            return Color(light: Color(hex: "F58426"), dark: Color(hex: "FF9E4D"))
        }
    }

    var secondaryAccentForegroundColor: Color {
        switch self {
        case .standard:
            return Color(light: .white, dark: .black)
        case .knicks:
            // Orange #F58426 is light in both schemes; white-on-orange fails
            // contrast (~2:1). A near-black warm ink reads ~9:1 either way and
            // keeps the orange accent legible without re-breaking the white-text
            // bug we just fixed on the food cards.
            return Color(hex: "1A1206")
        }
    }

    var participantPalette: [Color] {
        switch self {
        case .standard:
            return [
                Color(red: 0.424, green: 0.341, blue: 0.773),
                Color(red: 0.482, green: 0.361, blue: 0.749),
                Color(red: 0.118, green: 0.565, blue: 1.000),
                Color(red: 0.180, green: 0.800, blue: 0.443),
                Color(red: 0.910, green: 0.212, blue: 0.278),
                Color(red: 0.000, green: 0.780, blue: 0.941),
            ]
        case .knicks:
            // Official Knicks palette: blue #006BB6, orange #F58426, silver #BEC0C2,
            // plus supporting tints for avatar/pin variety.
            return [
                Color(hex: "006BB6"),
                Color(hex: "F58426"),
                Color(hex: "1D428A"),
                Color(hex: "BEC0C2"),
                Color(hex: "005EA8"),
                Color(hex: "C65312"),
            ]
        }
    }

    var categoryGradientFoodStart: Color {
        switch self {
        case .standard: return Color(red: 0.388, green: 0.302, blue: 0.718)
        case .knicks: return Color(hex: "006BB6")
        }
    }

    var categoryGradientFoodEnd: Color {
        switch self {
        case .standard: return Color(red: 0.235, green: 0.180, blue: 0.478)
        // Blue-forward: a darker shade of the official Knicks Blue #006BB6
        // (same hue, ~0.67x brightness) so brunch cards read blue — the primary
        // brand color — with strong white-title contrast (9.6:1). Orange stays
        // the pop accent, not the wallpaper. Strictly on-palette, no invented navy.
        case .knicks: return Color(hex: "00477A")
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
    var colorTheme: AppColorTheme {
        didSet { UserDefaults.standard.set(colorTheme.rawValue, forKey: "appColorTheme") }
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
        let rawColorTheme = d.string(forKey: "appColorTheme") ?? ""
        colorTheme = AppColorTheme(rawValue: rawColorTheme) ?? .standard
        boldText = d.bool(forKey: "boldText")
        largerText = d.bool(forKey: "largerText")
        reduceMotion = d.bool(forKey: "reduceMotion")
        eventSuggestionsEnabled = d.object(forKey: "eventSuggestionsEnabled") == nil
            ? true
            : d.bool(forKey: "eventSuggestionsEnabled")
        let storedRadius = d.integer(forKey: "eventSuggestionRadiusMiles")
        eventSuggestionRadiusMiles = storedRadius == 0 ? 2 : storedRadius
        let rawCategory = d.string(forKey: "eventSuggestionCategory") ?? ""
        eventSuggestionCategory = EventSuggestionCategoryPreference(rawValue: rawCategory) ?? .all
    }
}
