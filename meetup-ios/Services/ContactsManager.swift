import Contacts
import Foundation
import Observation

struct DeviceContact: Identifiable, Sendable {
    let id: String
    let displayName: String
    let phones: [String]
    let emails: [String]
}

struct MeContact: Sendable {
    let phone: String?
    let displayName: String?
    let imageData: Data?
}

@Observable
@MainActor
final class ContactsManager {
    var contacts: [DeviceContact] = []
    var authStatus: CNAuthorizationStatus = .notDetermined

    var hasContactsAccess: Bool {
        authStatus.rawValue >= CNAuthorizationStatus.authorized.rawValue
    }

    var needsSettingsForAccess: Bool {
        authStatus == .denied || authStatus == .restricted
    }

    func refreshAuthorizationStatus() {
        authStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func clear() {
        contacts = []
    }

    func load(force: Bool = false, requestsAccess: Bool = true) async {
        guard force || contacts.isEmpty else { return }

        authStatus = CNContactStore.authorizationStatus(for: .contacts)
        if authStatus == .notDetermined {
            guard requestsAccess else { return }
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            authStatus = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard hasContactsAccess else { return }

        // CNContactStore() init triggers IPC to contactsd — keep it off the main thread.
        let loaded: [DeviceContact] = await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
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
                let phones = contact.phoneNumbers.compactMap { ContactsManager.toE164($0.value.stringValue) }
                let emails = contact.emailAddresses.map {
                    ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                }
                result.append(DeviceContact(id: contact.identifier, displayName: name, phones: phones, emails: emails))
            }
            return result.sorted { $0.displayName < $1.displayName }
        }.value

        contacts = loaded
    }

    func fetchMeContact(requestsAccess: Bool = true) async -> MeContact? {
        authStatus = CNContactStore.authorizationStatus(for: .contacts)
        if authStatus == .notDetermined {
            guard requestsAccess else { return nil }
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            authStatus = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard hasContactsAccess else { return nil }

        return await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let keys = [
                CNContactPhoneNumbersKey,
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactImageDataKey,
                CNContactImageDataAvailableKey
            ] as [CNKeyDescriptor]

            let containerIdentifier = store.defaultContainerIdentifier()
            let predicate = CNContact.predicateForContactsInContainer(withIdentifier: containerIdentifier)
            guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
                  let contact = contacts.max(by: { scoreMeContact($0) < scoreMeContact($1) }) else {
                return nil
            }

            let displayName = [contact.givenName, contact.familyName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let phone = contact.phoneNumbers
                .compactMap { ContactsManager.toE164($0.value.stringValue) }
                .first
            let imageData = contact.isKeyAvailable(CNContactImageDataAvailableKey) &&
                contact.imageDataAvailable ? contact.imageData : nil

            guard phone != nil || !displayName.isEmpty || imageData != nil else { return nil }
            return MeContact(
                phone: phone,
                displayName: displayName.isEmpty ? nil : displayName,
                imageData: imageData
            )
        }.value
    }

    nonisolated static func toE164(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    func name(forPhone phone: String) -> String? {
        contacts.first { $0.phones.contains(phone) }?.displayName
    }

    func search(_ query: String) -> [DeviceContact] {
        guard !query.isEmpty else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return contacts.filter {
            $0.displayName.localizedStandardContains(q) ||
            $0.phones.contains { $0.contains(q) }
        }
    }
}

private func scoreMeContact(_ contact: CNContact) -> Int {
    var score = 0
    if contact.isKeyAvailable(CNContactImageDataAvailableKey), contact.imageDataAvailable { score += 4 }
    if !contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
    if !contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
    if contact.phoneNumbers.contains(where: { ContactsManager.toE164($0.value.stringValue) != nil }) { score += 1 }
    return score
}
