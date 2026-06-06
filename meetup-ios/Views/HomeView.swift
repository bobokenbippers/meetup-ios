import SwiftUI

struct HomeView: View {
    @Environment(NavigationState.self) private var navState
    private var locationManager: LocationManager { LocationManager.shared }

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
        .safeAreaInset(edge: .top, spacing: 0) {
            if locationManager.isTracking, let meetup = locationManager.trackingMeetup {
                LocationSharingBanner(meetup: meetup) {
                    nav.selectedTab = .meetups
                    nav.pendingMeetupId = meetup.id
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: locationManager.isTracking)
    }
}

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $settings.themePreference) {
                        Text("Light").tag(ThemePreference.light)
                        Text("Dark").tag(ThemePreference.dark)
                        Text("System").tag(ThemePreference.system)
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.coral)
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("APPEARANCE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                Section {
                    Toggle("Bold Text", isOn: $settings.boldText)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                    Toggle("Larger Text", isOn: $settings.largerText)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                    Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                } header: {
                    Text("ACCESSIBILITY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                Section {
                    Toggle("Sync Contacts", isOn: $settings.contactsEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                } header: {
                    Text("PRIVACY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(nil)
                }

                Section {
                    Button {
                        Task { await auth.signOut() }
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(Color.coral)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Settings")
            .preferredColorScheme(.dark)
        }
    }
}

