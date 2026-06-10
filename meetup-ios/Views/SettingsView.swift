import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    // Preferences persisted to Supabase (loaded on appear, saved on change).
    @State private var pushEnabled = true
    @State private var eventCancelledEnabled = true
    @State private var locationSharingEnabled = true
    @State private var prefsLoaded = false

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var contactsManager = ContactsManager()
    @State private var isSyncingContacts = false
    @State private var contactSyncMessage: String?

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
                    Toggle(isOn: Binding(
                        get: { settings.contactsEnabled },
                        set: { setContactSyncEnabled($0) }
                    )) {
                        HStack(spacing: 10) {
                            Text("Sync Contacts")
                            if isSyncingContacts {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.coral)
                            }
                        }
                    }
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)

                    if let contactSyncMessage {
                        Text(contactSyncMessage)
                            .font(.caption2)
                            .foregroundStyle(Color(white: 0.55))
                            .listRowBackground(Color.appSurface)
                    }

                    if contactsManager.needsSettingsForAccess {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            aboutRow("Open iOS Settings", systemImage: "gear")
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.appSurface)
                    }
                } header: {
                    sectionHeader("PRIVACY")
                } footer: {
                    Text("When off, your live location and ETA are never shared during meetups. Contact sync only reads your device contacts locally to suggest people you may know.")
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

                    Button {
                        openURL(feedbackURL)
                    } label: {
                        aboutRow("Send Feedback", systemImage: "envelope")
                    }
                    .buttonStyle(.plain)
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
        .task {
            await loadPrefs()
            refreshContactSyncState()
        }
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

    private func aboutRow(_ title: String, systemImage: String = "arrow.up.right") -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Image(systemName: systemImage)
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

    private var feedbackURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "gautam.pappu@utexas.edu"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Squad Brunch Beta Feedback"),
            URLQueryItem(name: "body", value: feedbackBody)
        ]
        return components.url ?? URL(string: "mailto:gautam.pappu@utexas.edu")!
    }

    private var feedbackBody: String {
        """


        ---
        App: Squad Brunch \(appVersion)
        User ID: \(auth.profile?.id.uuidString ?? "unknown")
        Display Name: \(auth.profile?.displayName ?? "unknown")
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
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

    private func refreshContactSyncState() {
        contactsManager.refreshAuthorizationStatus()
        guard settings.contactsEnabled else {
            contactSyncMessage = nil
            return
        }
        if contactsManager.needsSettingsForAccess {
            settings.contactsEnabled = false
            contactSyncMessage = "Contacts permission is off. Enable it in iOS Settings to sync contacts."
        }
    }

    private func setContactSyncEnabled(_ enabled: Bool) {
        if enabled {
            settings.contactsEnabled = true
            contactSyncMessage = nil
            isSyncingContacts = true
            Task {
                await contactsManager.load(force: true)
                isSyncingContacts = false
                if contactsManager.hasContactsAccess {
                    let count = contactsManager.contacts.count
                    contactSyncMessage = count == 0
                        ? "Contacts synced, but no phone numbers were found."
                        : "Synced \(count) contacts."
                } else {
                    settings.contactsEnabled = false
                    contactSyncMessage = "Contacts permission is off. Enable it in iOS Settings to sync contacts."
                }
            }
        } else {
            settings.contactsEnabled = false
            contactsManager.clear()
            contactSyncMessage = "Contact sync is off."
        }
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
