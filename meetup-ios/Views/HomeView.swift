import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            MeetupsListView()
                .tabItem { Label("Meetups", systemImage: "person.2.circle") }
            PeopleListView()
                .tabItem { Label("People", systemImage: "person.crop.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(Color.coral)
    }
}

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var themePreference = ThemePreference.system
    @State private var boldText = false
    @State private var largerText = false
    @State private var reduceMotion = false
    @State private var contactsEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $themePreference) {
                        Text("Light").tag(ThemePreference.light)
                        Text("Dark").tag(ThemePreference.dark)
                        Text("System").tag(ThemePreference.system)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Accessibility") {
                    Toggle("Bold Text", isOn: $boldText)
                    Toggle("Larger Text", isOn: $largerText)
                    Toggle("Reduce Motion", isOn: $reduceMotion)
                }

                Section("Privacy") {
                    Toggle("Sync Contacts", isOn: $contactsEnabled)
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
            .preferredColorScheme(colorScheme)
            .task { loadSettings() }
            .onChange(of: themePreference) { _, _ in saveSettings() }
            .onChange(of: boldText) { _, _ in saveSettings() }
            .onChange(of: largerText) { _, _ in saveSettings() }
            .onChange(of: reduceMotion) { _, _ in saveSettings() }
            .onChange(of: contactsEnabled) { _, _ in saveSettings() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch themePreference {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        let storedTheme: ThemePreference
        if let rawTheme = defaults.string(forKey: "themePreference") {
            storedTheme = ThemePreference(rawValue: rawTheme) ?? .system
        } else {
            storedTheme = .system
        }
        if themePreference != storedTheme { themePreference = storedTheme }
        let storedBold = defaults.bool(forKey: "boldText")
        let storedLarger = defaults.bool(forKey: "largerText")
        let storedReduceMotion = defaults.bool(forKey: "reduceMotion")
        let storedContacts = defaults.bool(forKey: "contactsEnabled")
        if boldText != storedBold { boldText = storedBold }
        if largerText != storedLarger { largerText = storedLarger }
        if reduceMotion != storedReduceMotion { reduceMotion = storedReduceMotion }
        if contactsEnabled != storedContacts { contactsEnabled = storedContacts }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(themePreference.rawValue, forKey: "themePreference")
        defaults.set(boldText, forKey: "boldText")
        defaults.set(largerText, forKey: "largerText")
        defaults.set(reduceMotion, forKey: "reduceMotion")
        defaults.set(contactsEnabled, forKey: "contactsEnabled")
    }
}

enum ThemePreference: String {
    case light
    case dark
    case system
}
