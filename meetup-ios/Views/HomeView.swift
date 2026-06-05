import SwiftUI

struct HomeView: View {
    @Environment(NavigationState.self) private var navState

    var body: some View {
        @Bindable var nav = navState
        TabView(selection: $nav.selectedTab) {
            MeetupsListView()
                .tabItem { Label("Meetups", systemImage: "person.2.circle") }
                .tag(NavigationState.Tab.meetups)
            PeopleListView()
                .tabItem { Label("People", systemImage: "person.crop.circle") }
                .tag(NavigationState.Tab.people)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(NavigationState.Tab.settings)
        }
        .tint(Color.coral)
    }
}

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.themePreference) {
                        Text("Light").tag(ThemePreference.light)
                        Text("Dark").tag(ThemePreference.dark)
                        Text("System").tag(ThemePreference.system)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Accessibility") {
                    Toggle("Bold Text", isOn: $settings.boldText)
                    Toggle("Larger Text", isOn: $settings.largerText)
                    Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                }

                Section("Privacy") {
                    Toggle("Sync Contacts", isOn: $settings.contactsEnabled)
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
            .preferredColorScheme(colorScheme(for: settings.themePreference))
        }
    }

    private func colorScheme(for preference: ThemePreference) -> ColorScheme? {
        switch preference {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

