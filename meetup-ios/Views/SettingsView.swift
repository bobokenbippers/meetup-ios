import SwiftUI
import UIKit
import PhotosUI
import UserNotifications
import Contacts

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    // Preferences persisted to Supabase (loaded on appear, saved on change).
    @State private var pushEnabled = true
    @State private var eventCancelledEnabled = true
    @State private var locationSharingEnabled = true
    @State private var prefsLoaded = false
    @State private var notificationMessage: String?

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var contactsManager = ContactsManager()
    @State private var isRequestingContacts = false
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var isUploadingProfilePhoto = false
    @State private var profilePhotoMessage: String?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                // MARK: Account
                Section {
                    HStack(spacing: 12) {
                        ProfileAvatarView(profile: auth.profile, size: 54, fontSize: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.coral.opacity(0.35), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Profile Photo")
                                .foregroundStyle(DS.Color.textPrimary)
                            if isUploadingProfilePhoto {
                                Text("Uploading...")
                                    .font(.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            } else if let profilePhotoMessage {
                                Text(profilePhotoMessage)
                                    .font(.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }

                        Spacer()

                        PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                            Text(auth.profile?.avatarUrl == nil ? "Upload" : "Change")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isUploadingProfilePhoto ? DS.Color.textSecondary : Color.coral)
                        }
                        .disabled(isUploadingProfilePhoto)
                    }
                    .listRowBackground(Color.appSurface)

                    NavigationLink {
                        EditDisplayNameView(currentName: auth.profile?.displayName ?? "")
                    } label: {
                        HStack {
                            Text("Display Name")
                                .foregroundStyle(DS.Color.textPrimary)
                            Spacer()
                            Text(auth.profile?.displayName ?? "Not set")
                                .foregroundStyle(DS.Color.textSecondary)
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
                    Picker("Appearance", selection: $settings.themePreference) {
                        ForEach(ThemePreference.allCases, id: \.self) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.appSurface)

                    Picker("Team Theme", selection: $settings.colorTheme) {
                        ForEach(AppColorTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
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
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)
                    Toggle("Larger Text", isOn: $settings.largerText)
                        .tint(Color.coral)
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)
                    Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                        .tint(Color.coral)
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)
                } header: {
                    sectionHeader("ACCESSIBILITY")
                } footer: {
                    Text("Bold and Larger Text apply across the app. Reduce Motion calms animated RSVP and meetup effects.")
                        .font(.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                // MARK: Event Suggestions
                Section {
                    Toggle("Event Suggestions", isOn: $settings.eventSuggestionsEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)

                    Picker("Event Type", selection: $settings.eventSuggestionCategory) {
                        ForEach(EventSuggestionCategoryPreference.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .tint(Color.coral)
                    .foregroundStyle(settings.eventSuggestionsEnabled ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .listRowBackground(Color.appSurface)
                    .disabled(!settings.eventSuggestionsEnabled)

                    Stepper(
                        "Within \(settings.eventSuggestionRadiusMiles) mile\(settings.eventSuggestionRadiusMiles == 1 ? "" : "s")",
                        value: $settings.eventSuggestionRadiusMiles,
                        in: 1...50,
                        step: 1
                    )
                    .tint(Color.coral)
                    .foregroundStyle(settings.eventSuggestionsEnabled ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .listRowBackground(Color.appSurface)
                    .disabled(!settings.eventSuggestionsEnabled)
                } header: {
                    sectionHeader("EVENT SUGGESTIONS")
                } footer: {
                    Text("Used for the Happening Near You row on Meetups.")
                        .font(.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                // MARK: Notifications
                Section {
                    Toggle("Push Notifications", isOn: $pushEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)
                        .onChange(of: pushEnabled) { _, newValue in
                            updatePushNotifications(newValue)
                        }
                    Toggle("Event Cancelled", isOn: $eventCancelledEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(pushEnabled ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .listRowBackground(Color.appSurface)
                        .disabled(!pushEnabled)
                        .onChange(of: eventCancelledEnabled) { _, _ in persist() }
                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(.caption2)
                            .foregroundStyle(DS.Color.textSecondary)
                            .listRowBackground(Color.appSurface)
                    }
                    if notificationMessage?.contains("iOS Settings") == true {
                        Button {
                            openSystemSettings()
                        } label: {
                            aboutRow("Open iOS Settings", systemImage: "gear")
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.appSurface)
                    }
                } header: {
                    sectionHeader("NOTIFICATIONS")
                } footer: {
                    Text("\"Event Cancelled\" alerts you when a host cancels a meetup you joined.")
                        .font(.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                // MARK: Privacy
                Section {
                    Toggle("Location Sharing", isOn: $locationSharingEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(DS.Color.textPrimary)
                        .listRowBackground(Color.appSurface)
                        .onChange(of: locationSharingEnabled) { _, newValue in
                            if !newValue { LocationManager.shared.stopTracking() }
                            persist()
                        }
                    HStack(spacing: 10) {
                        Text("Contacts")
                            .foregroundStyle(DS.Color.textPrimary)
                        if isRequestingContacts {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.coral)
                        }
                        Spacer()
                        Text(contactsAccessLabel)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .listRowBackground(Color.appSurface)

                    if contactsManager.authStatus == .notDetermined {
                        Button {
                            isRequestingContacts = true
                            Task {
                                await contactsManager.load(force: true)
                                contactsManager.refreshAuthorizationStatus()
                                isRequestingContacts = false
                            }
                        } label: {
                            aboutRow("Allow Contacts Access", systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.appSurface)
                    } else if contactsManager.needsSettingsForAccess {
                        Button {
                            openSystemSettings()
                        } label: {
                            aboutRow("Open iOS Settings", systemImage: "gear")
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.appSurface)
                    }

                    NavigationLink {
                        PrivacyAuditLogView()
                    } label: {
                        aboutRow("Privacy Log", systemImage: "lock.shield")
                    }
                    .listRowBackground(Color.appSurface)
                } header: {
                    sectionHeader("PRIVACY")
                } footer: {
                    Text("When off, your live location and ETA are never shared during meetups. Contact suggestions read your device contacts locally to suggest people you may know — they're on whenever you allow Contacts access, and you can turn them off any time in iOS Settings.")
                        .font(.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                // MARK: About
                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(DS.Color.textPrimary)
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(DS.Color.textSecondary)
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

        }
        .task {
            await loadPrefs()
            contactsManager.refreshAuthorizationStatus()
        }
        .onChange(of: selectedProfilePhoto) { _, item in
            guard let item else { return }
            Task { await uploadProfilePhoto(item) }
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
            Text("This deactivates your account and signs you out. Send feedback if you need your data fully erased.")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.Color.textSecondary)
            .textCase(nil)
    }

    private func aboutRow(_ title: String, systemImage: String = "arrow.up.right") -> some View {
        HStack {
            Text(title).foregroundStyle(DS.Color.textPrimary)
            Spacer()
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
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

    private func updatePushNotifications(_ enabled: Bool) {
        guard prefsLoaded else { return }
        if enabled {
            notificationMessage = nil
            Task {
                let granted = await NotificationService.shared.requestAuthorizationAndRegister()
                await MainActor.run {
                    if granted {
                        notificationMessage = "Push notifications are on."
                    } else {
                        pushEnabled = false
                        notificationMessage = "Notifications are blocked. Enable them in iOS Settings."
                    }
                    persist()
                }
            }
        } else {
            if notificationMessage?.contains("blocked") == true {
                persist()
                return
            }
            notificationMessage = "Push notifications are off."
            persist()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var contactsAccessLabel: String {
        if contactsManager.hasContactsAccess { return "Allowed" }
        if contactsManager.authStatus == .notDetermined { return "Not set" }
        return "Off"
    }

    private func uploadProfilePhoto(_ item: PhotosPickerItem) async {
        isUploadingProfilePhoto = true
        profilePhotoMessage = nil
        defer {
            isUploadingProfilePhoto = false
            selectedProfilePhoto = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                profilePhotoMessage = "Couldn't load that photo."
                return
            }
            let didUpdate = await auth.updateProfilePhoto(image)
            if didUpdate {
                profilePhotoMessage = "Profile photo updated."
            } else {
                profilePhotoMessage = auth.error ?? "Couldn't upload that photo."
            }
        } catch is CancellationError {
            return
        } catch {
            profilePhotoMessage = "Couldn't load that photo."
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
                    .foregroundStyle(DS.Color.textPrimary)
                    .listRowBackground(Color.appSurface)
            } header: {
                Text("DISPLAY NAME")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Edit Name")
        .navigationBarTitleDisplayMode(.inline)

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
