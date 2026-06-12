import SwiftUI
import UIKit
import PhotosUI
import UserNotifications

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
    @State private var isSyncingContacts = false
    @State private var contactSyncMessage: String?
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
                                .foregroundStyle(.white)
                            if isUploadingProfilePhoto {
                                Text("Uploading...")
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.6))
                            } else if let profilePhotoMessage {
                                Text(profilePhotoMessage)
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.6))
                            }
                        }

                        Spacer()

                        PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                            Text(auth.profile?.avatarUrl == nil ? "Upload" : "Change")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isUploadingProfilePhoto ? Color(white: 0.45) : Color.coral)
                        }
                        .disabled(isUploadingProfilePhoto)
                    }
                    .listRowBackground(Color.appSurface)

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
                } footer: {
                    Text("Bold and Larger Text apply across the app. Reduce Motion calms animated RSVP and meetup effects.")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.4))
                }

                // MARK: Event Suggestions
                Section {
                    Toggle("Event Suggestions", isOn: $settings.eventSuggestionsEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)

                    Picker("Event Type", selection: $settings.eventSuggestionCategory) {
                        ForEach(EventSuggestionCategoryPreference.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .tint(Color.coral)
                    .foregroundStyle(settings.eventSuggestionsEnabled ? .white : Color(white: 0.45))
                    .listRowBackground(Color.appSurface)
                    .disabled(!settings.eventSuggestionsEnabled)

                    Stepper(
                        "Within \(settings.eventSuggestionRadiusMiles) miles",
                        value: $settings.eventSuggestionRadiusMiles,
                        in: 5...50,
                        step: 5
                    )
                    .tint(Color.coral)
                    .foregroundStyle(settings.eventSuggestionsEnabled ? .white : Color(white: 0.45))
                    .listRowBackground(Color.appSurface)
                    .disabled(!settings.eventSuggestionsEnabled)
                } header: {
                    sectionHeader("EVENT SUGGESTIONS")
                } footer: {
                    Text("Used for the Happening Near You row on Meetups.")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.4))
                }

                // MARK: Notifications
                Section {
                    Toggle("Push Notifications", isOn: $pushEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.appSurface)
                        .onChange(of: pushEnabled) { _, newValue in
                            updatePushNotifications(newValue)
                        }
                    Toggle("Event Cancelled", isOn: $eventCancelledEnabled)
                        .tint(Color.coral)
                        .foregroundStyle(pushEnabled ? .white : Color(white: 0.45))
                        .listRowBackground(Color.appSurface)
                        .disabled(!pushEnabled)
                        .onChange(of: eventCancelledEnabled) { _, _ in persist() }
                    if let notificationMessage {
                        Text(notificationMessage)
                            .font(.caption2)
                            .foregroundStyle(Color(white: 0.55))
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
                    if contactSyncMessage?.contains("iOS Settings") == true {
                        Button {
                            openSystemSettings()
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

    private func updatePushNotifications(_ enabled: Bool) {
        guard prefsLoaded else { return }
        if enabled {
            notificationMessage = nil
            Task {
                let granted = await requestNotificationAuthorization()
                await MainActor.run {
                    if granted {
                        notificationMessage = "Push notifications are on."
                        UIApplication.shared.registerForRemoteNotifications()
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

    private func requestNotificationAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
