import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppSettings.self) private var settings

    // Preferences persisted to Supabase (loaded on appear, saved on change).
    @State private var pushEnabled = true
    @State private var eventCancelledEnabled = true
    @State private var locationSharingEnabled = true
    @State private var prefsLoaded = false

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                // MARK: Account
                Section {
                    NavigationLink {
                        EditDisplayNameView(currentName: auth.profile?.displayName ?? "")
                    } label: {
                        HStack {
                            Text("Display Name")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(auth.profile?.displayName ?? "Not set")
                                .foregroundStyle(Color(white: 0.6))
                        }
                    }
                    .listRowBackground(Color.appSurface)

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete Account")
                            .foregroundStyle(Color.statusLate)
                    }
                    .listRowBackground(Color.appSurface)
                } header: {
                    sectionHeader("ACCOUNT")
                }

                // MARK: Appearance
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
                    sectionHeader("APPEARANCE")
                }

                // MARK: Accessibility
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
                    sectionHeader("ACCESSIBILITY")
                }

                // MARK: Notifications
                Section {
                    Toggle("Push Notifications", isOn: $pushEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                        .onChange(of: pushEnabled) { _, _ in persist() }
                    Toggle("Event Cancelled", isOn: $eventCancelledEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(pushEnabled ? .white : Color(white: 0.45))
                        .listRowBackground(Color.appSurface)
                        .disabled(!pushEnabled)
                        .onChange(of: eventCancelledEnabled) { _, _ in persist() }
                } header: {
                    sectionHeader("NOTIFICATIONS")
                } footer: {
                    Text("Turn off Push Notifications to silence everything. \"Event Cancelled\" alerts you when a host cancels a meetup you joined.")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.4))
                }

                // MARK: Privacy
                Section {
                    Toggle("Location Sharing", isOn: $locationSharingEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                        .onChange(of: locationSharingEnabled) { _, newValue in
                            if !newValue { LocationManager.shared.stopTracking() }
                            persist()
                        }
                    Toggle("Sync Contacts", isOn: $settings.contactsEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                } header: {
                    sectionHeader("PRIVACY")
                } footer: {
                    Text("When off, your live location and ETA are never shared during meetups.")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.4))
                }

                // MARK: About
                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.white)
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(Color(white: 0.6))
                    }
                    .listRowBackground(Color.appSurface)

                    Link(destination: URL(string: "https://squadbrunch.app/terms")!) {
                        aboutRow("Terms of Service")
                    }
                    .listRowBackground(Color.appSurface)

                    Link(destination: URL(string: "https://squadbrunch.app/support")!) {
                        aboutRow("Support")
                    }
                    .listRowBackground(Color.appSurface)
                } header: {
                    sectionHeader("ABOUT")
                }

                // MARK: Sign Out
                Section {
                    Button {
                        showSignOutConfirm = true
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
        .task { await loadPrefs() }
        .confirmationDialog("Sign out of Squad Brunch?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await auth.deactivateAndSignOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deactivates your account and signs you out. Contact support to fully erase your data.")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(white: 0.4))
            .textCase(nil)
    }

    private func aboutRow(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(Color(white: 0.4))
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func loadPrefs() async {
        do {
            if let prefs = try await UserSettingsService.shared.fetch() {
                pushEnabled = prefs.pushNotificationsEnabled
                eventCancelledEnabled = prefs.eventCancelledEnabled
                locationSharingEnabled = prefs.locationSharingEnabled
            }
            prefsLoaded = true
        } catch is CancellationError {
            return
        } catch {
            // Keep optimistic defaults if the fetch fails; user can still toggle.
            prefsLoaded = true
        }
    }

    private func persist() {
        guard prefsLoaded, let userId = auth.profile?.id else { return }
        let snapshot = UserSettings(
            userId: userId,
            pushNotificationsEnabled: pushEnabled,
            eventCancelledEnabled: eventCancelledEnabled,
            locationSharingEnabled: locationSharingEnabled
        )
        Task { try? await UserSettingsService.shared.save(snapshot) }
    }
}

// MARK: - Edit Display Name

private struct EditDisplayNameView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isSaving = false

    init(currentName: String) {
        _name = State(initialValue: currentName)
    }

    var body: some View {
        List {
            Section {
                TextField("Display name", text: $name)
                    .foregroundStyle(.white)
                    .listRowBackground(Color.appSurface)
            } header: {
                Text("DISPLAY NAME")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.4))
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Edit Name")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        isSaving = true
                        await auth.updateDisplayName(name)
                        isSaving = false
                        dismiss()
                    }
                }
                .tint(Color.coral)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
