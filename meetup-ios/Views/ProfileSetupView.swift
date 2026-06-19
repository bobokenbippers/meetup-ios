import SwiftUI
import Supabase
import UIKit

// MARK: - Profile setup view

struct ProfileSetupView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var contactsManager = ContactsManager()
    @State private var displayName = ""
    @State private var phone = ""
    @State private var profileImage: UIImage?
    @State private var isSaving = false
    @State private var isImportingAppleID = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            profilePhotoPreview
            Text("One more thing")
                .font(.largeTitle.bold())
            Text("Add your name and phone number so friends can invite you to meetups.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .padding(.horizontal)
            HStack(spacing: 0) {
                Text("🇺🇸 +1")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                TextField("(646) 946-6861", text: $phone)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: phone) { _, newValue in
                        let candidate = PhoneFormatter.format(newValue)
                        if phone != candidate { phone = candidate }
                    }
            }
            .padding(.horizontal)
            Button {
                Task { await importAppleIDContactInfo() }
            } label: {
                Label(
                    isImportingAppleID ? "Importing..." : "Use Apple ID",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isImportingAppleID || isSaving)
            Button("Save") {
                Task { await save() }
            }
            .buttonStyle(.glassProminent)
            .disabled(isSaving || normalizedPhone == nil)
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Spacer()
        }
        .padding()
        .task {
            if displayName.isEmpty, let existingName = auth.profile?.displayName {
                displayName = existingName
            }
        }
    }

    @ViewBuilder
    private var profilePhotoPreview: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.14))
                Image(systemName: "person.crop.circle.fill")
                    .scaledFont(size: 54)
                    .foregroundStyle(.tint)
            }
            .frame(width: 88, height: 88)
        }
    }

    private var normalizedPhone: String? { PhoneFormatter.toE164(phone) }

    private var normalizedDisplayName: String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func importAppleIDContactInfo() async {
        isImportingAppleID = true
        error = nil
        defer { isImportingAppleID = false }

        guard let meContact = await contactsManager.fetchMeContact() else {
            if contactsManager.needsSettingsForAccess {
                error = "Allow Contacts access in Settings to import Apple ID info."
            }
            return
        }

        if let importedDisplayName = meContact.displayName {
            displayName = importedDisplayName
        }
        if let importedPhone = meContact.phone {
            let digits = importedPhone.hasPrefix("+1") ? String(importedPhone.dropFirst(2)) : importedPhone
            phone = PhoneFormatter.format(digits)
        }
        if let imageData = meContact.imageData,
           let image = UIImage(data: imageData) {
            profileImage = image
        }
    }

    private func save() async {
        guard let phone = normalizedPhone, let userId = auth.session?.user.id else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            struct ProfileSetupUpdate: Encodable {
                let phoneE164: String
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case phoneE164 = "phone_e164"
                    case displayName = "display_name"
                }
            }

            try await SupabaseManager.shared.client
                .from("profiles")
                .update(ProfileSetupUpdate(phoneE164: phone, displayName: normalizedDisplayName))
                .eq("id", value: userId)
                .execute()
            if let profileImage {
                let didUpdatePhoto = await auth.updateProfilePhoto(profileImage)
                if !didUpdatePhoto {
                    self.error = auth.error ?? "Couldn't upload that photo."
                    return
                }
            }
            await auth.loadProfile(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
