import SwiftUI

enum ThemePreference: String {
    case light
    case dark
    case system
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

    init() {
        let d = UserDefaults.standard
        let rawTheme = d.string(forKey: "themePreference") ?? ""
        themePreference = ThemePreference(rawValue: rawTheme) ?? .system
        boldText = d.bool(forKey: "boldText")
        largerText = d.bool(forKey: "largerText")
        reduceMotion = d.bool(forKey: "reduceMotion")
        contactsEnabled = d.bool(forKey: "contactsEnabled")
    }
}
