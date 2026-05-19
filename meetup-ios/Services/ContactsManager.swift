import Contacts
import Observation

struct DeviceContact: Identifiable {
    let id: String
    let displayName: String
    let phones: [String]
    let emails: [String]
}

@Observable
final class ContactsManager {
    var contacts: [DeviceContact] = []
    var authStatus: CNAuthorizationStatus = .notDetermined

    func load() async {
        let store = CNContactStore()
        authStatus = CNContactStore.authorizationStatus(for: .contacts)
        if authStatus == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
            authStatus = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard authStatus != .denied && authStatus != .restricted && authStatus != .notDetermined else { return }
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactIdentifierKey
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [DeviceContact] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty else { return }
            let phones = contact.phoneNumbers.compactMap { Self.toE164($0.value.stringValue) }
            let emails = contact.emailAddresses.map {
                ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces)
            }
            result.append(DeviceContact(id: contact.identifier, displayName: name, phones: phones, emails: emails))
        }
        contacts = result.sorted { $0.displayName < $1.displayName }
    }

    static func toE164(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    func search(_ query: String) -> [DeviceContact] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return contacts.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.phones.contains { $0.contains(q) }
        }
    }
}
