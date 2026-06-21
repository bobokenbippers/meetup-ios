import SwiftUI
import Contacts
import ContactsUI
import Supabase

// MARK: - Contact picker bridge

struct ContactPhonePicker: UIViewControllerRepresentable {
    var onPick: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String) -> Void
        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard let phone = contactProperty.value as? CNPhoneNumber else { return }
            let digits = phone.stringValue.filter { $0.isNumber }
            let e164: String
            if digits.count == 10 { e164 = "+1" + digits }
            else if digits.count == 11, digits.hasPrefix("1") { e164 = "+" + digits }
            else { return }
            onPick(e164)
        }
    }
}

// MARK: - Profile setup view

struct ProfileSetupView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var phone = ""
    @State private var isSaving = false
    @State private var showContactPicker = false
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
            Button {
                showContactPicker = true
            } label: {
                Label("Use from Contacts", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
        .sheet(isPresented: $showContactPicker) {
            ContactPhonePicker { e164 in
                let digits = e164.hasPrefix("+1") ? String(e164.dropFirst(2)) : e164
                phone = PhoneFormatter.format(digits)
                showContactPicker = false
            }
            .ignoresSafeArea()
        }
    }

    private var normalizedPhone: String? { PhoneFormatter.toE164(phone) }

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
