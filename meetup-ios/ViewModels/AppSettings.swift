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
    case aperitif
    case coastal

    var id: String { rawValue }

    static var current: AppColorTheme {
        let rawTheme = UserDefaults.standard.string(forKey: "appColorTheme") ?? ""
        return AppColorTheme(rawValue: rawTheme) ?? .standard
    }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .aperitif: return "Aperitif"
        case .coastal:  return "Coastal"
        }
    }

    var accentColor: Color {
        switch self {
        case .standard:
            return Color(light: Color(hex: "6C57C5"), dark: Color(hex: "8A78E0"))
        case .aperitif:
            return Color(light: Color(hex: "A83F5F"), dark: Color(hex: "FF8AA6"))
        case .coastal:
            return Color(light: Color(hex: "0F7C80"), dark: Color(hex: "4FD1C5"))
        }
    }

    var accentForegroundColor: Color {
        switch self {
        case .standard, .aperitif:
            return Color(light: .white, dark: .black)
        case .coastal:
            return Color.white
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .standard:
            return Color(light: Color(hex: "D95F76"), dark: Color(hex: "FF9A7A"))
        case .aperitif:
            return Color(light: Color(hex: "C78A2F"), dark: Color(hex: "F2C46D"))
        case .coastal:
            return Color(light: Color(hex: "D0643A"), dark: Color(hex: "FFB86B"))
        }
    }

    var secondaryAccentForegroundColor: Color {
        switch self {
        case .standard, .aperitif:
            return Color(light: .white, dark: .black)
        case .coastal:
            return Color(light: .white, dark: .black)
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
        case .aperitif:
            return [
                Color(hex: "A83F5F"),
                Color(hex: "C78A2F"),
                Color(hex: "6C57C5"),
                Color(hex: "2F7D67"),
                Color(hex: "D95F76"),
                Color(hex: "4467A8"),
            ]
        case .coastal:
            return [
                Color(hex: "0F7C80"),
                Color(hex: "D0643A"),
                Color(hex: "4B6FA8"),
                Color(hex: "7B8F3A"),
                Color(hex: "9C5DA8"),
                Color(hex: "2F9C73"),
            ]
        }
    }

    var categoryGradientFoodStart: Color {
        switch self {
        case .standard: return Color(red: 0.388, green: 0.302, blue: 0.718)
        case .aperitif: return Color(hex: "A83F5F")
        case .coastal:  return Color(hex: "0F7C80")
        }
    }

    var categoryGradientFoodEnd: Color {
        switch self {
        case .standard: return Color(red: 0.235, green: 0.180, blue: 0.478)
        case .aperitif: return Color(hex: "5E2C56")
        case .coastal:  return Color(hex: "164E63")
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
        eventSuggestionRadiusMiles = storedRadius == 0 ? 5 : storedRadius
        let rawCategory = d.string(forKey: "eventSuggestionCategory") ?? ""
        eventSuggestionCategory = EventSuggestionCategoryPreference(rawValue: rawCategory) ?? .all
    }
}
