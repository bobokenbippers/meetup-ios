import SwiftUI
import Supabase

struct ProfileSetupView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var phone = ""
    @State private var isSaving = false
    @State private var isFetchingMeContact = false
    @State private var showsAppleIDContactButton = false
    @State private var contactsManager = ContactsManager()
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "phone.circle.fill")
                .scaledFont(size: 60)
                .foregroundStyle(.tint)
            Text("One more thing")
                .font(.largeTitle.bold())
            Text("Add your phone number so friends can invite you to meetups.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
            if showsAppleIDContactButton {
                Button {
                    Task { await useAppleIDContactInfo() }
                } label: {
                    if isFetchingMeContact {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Use Apple ID", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isFetchingMeContact)
            }
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
            await refreshAppleIDContactAvailability()
        }
    }

    private var normalizedPhone: String? { PhoneFormatter.toE164(phone) }

    private func refreshAppleIDContactAvailability() async {
        contactsManager.refreshAuthorizationStatus()
        if contactsManager.authStatus == .notDetermined {
            showsAppleIDContactButton = true
            return
        }

        guard contactsManager.hasContactsAccess else {
            showsAppleIDContactButton = false
            return
        }

        showsAppleIDContactButton = await contactsManager.fetchMeContact(requestsAccess: false) != nil
    }

    private func useAppleIDContactInfo() async {
        isFetchingMeContact = true
        defer { isFetchingMeContact = false }

        guard let e164 = await contactsManager.fetchMeContact() else {
            showsAppleIDContactButton = false
            return
        }

        let digits = e164.hasPrefix("+1") ? String(e164.dropFirst(2)) : e164
        phone = PhoneFormatter.format(digits)
        showsAppleIDContactButton = true
        error = nil
    }

    private func save() async {
        guard let phone = normalizedPhone, let userId = auth.session?.user.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await SupabaseManager.shared.client
                .from("profiles")
                .update(["phone_e164": phone])
                .eq("id", value: userId)
                .execute()
            await auth.loadProfile(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
