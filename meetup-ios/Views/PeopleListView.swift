import SwiftUI
import Supabase
import Contacts

struct PeopleListView: View {
    @State private var people: [Profile] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var phoneSearch = ""
    @State private var foundUser: FoundUser?
    @State private var isSearching = false
    @State private var contactsManager = ContactsManager()
    @State private var contactSuggestions: [DeviceContact] = []

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else {
                    List {
                        Section("Add Friend") {
                            if contactsManager.authStatus == .denied {
                                Label("Contacts access denied — tap to open Settings", systemImage: "exclamationmark.circle")
                                    .font(.caption).foregroundStyle(.red)
                                    .onTapGesture {
                                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                                    }
                            }
                            HStack {
                                TextField("Name or +1 (646) 946-6861", text: $phoneSearch)
                                    .keyboardType(.default)
                                    .autocorrectionDisabled()
                                    .onChange(of: phoneSearch) { _, v in
                                        if v.contains(where: { $0.isLetter }) {
                                            contactSuggestions = Array(contactsManager.search(v).prefix(5))
                                        } else {
                                            let raw = v.hasPrefix("+1") ? String(v.dropFirst(2)) : v
                                            let digitsOnly = String(raw.filter { $0.isNumber }.prefix(10))
                                            let formatted = formatPhone(digitsOnly)
                                            if phoneSearch != formatted {
                                                phoneSearch = formatted
                                            } else {
                                                contactSuggestions = Array(contactsManager.search(digitsOnly).prefix(5))
                                            }
                                        }
                                    }
                                if isSearching {
                                    ProgressView()
                                } else {
                                    Button("Search") { Task { await searchUser() } }
                                        .disabled({
                                            let raw = phoneSearch.hasPrefix("+1") ? String(phoneSearch.dropFirst(2)) : phoneSearch
                                            return raw.filter { $0.isNumber }.count < 10
                                        }())
                                }
                            }
                            ForEach(contactSuggestions) { contact in
                                Button { Task { await selectContact(contact) } } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.displayName).foregroundStyle(.primary)
                                        Text(contact.phones.first ?? contact.emails.first ?? "")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if let user = foundUser {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName).font(.subheadline)
                                        Text(user.phone).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Add") { Task { await addFriend(user) } }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                }
                            }
                        }

                        if !people.isEmpty {
                            Section("From Meetups") {
                                ForEach(people) { person in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(person.displayName ?? "Unknown")
                                            .font(.headline)
                                        if let phone = person.phoneE164 {
                                            Text(phone)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .onDelete { indices in Task { await removePeople(at: indices) } }
                            }
                        } else if hasLoaded {
                            Section {
                                Text("People you've had meetups with will appear here.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            }
            .navigationTitle("People")
            .task {
                await load()
                await contactsManager.load()
                refreshSuggestions()
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func refreshSuggestions() {
        guard !phoneSearch.isEmpty else { contactSuggestions = []; return }
        if phoneSearch.contains(where: { $0.isLetter }) {
            contactSuggestions = Array(contactsManager.search(phoneSearch).prefix(5))
        } else {
            let raw = phoneSearch.hasPrefix("+1") ? String(phoneSearch.dropFirst(2)) : phoneSearch
            let digits = raw.filter { $0.isNumber }
            contactSuggestions = digits.isEmpty ? [] : Array(contactsManager.search(digits).prefix(5))
        }
    }

    private func load() async {
        do {
            people = try await MeetupService.shared.getPeopleFromMeetups()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func formatPhone(_ digits: String) -> String {
        switch digits.count {
        case 0:     return ""
        case 1...3: return "+1 (\(digits)"
        case 4...6: return "+1 (\(digits.prefix(3))) \(digits.dropFirst(3))"
        default:    return "+1 (\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
        }
    }

    private func searchUser() async {
        let raw = phoneSearch.hasPrefix("+1") ? String(phoneSearch.dropFirst(2)) : phoneSearch
        let digits = raw.filter { $0.isNumber }
        guard digits.count == 10 else { return }
        let e164 = "+1" + digits
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        isSearching = true
        foundUser = nil
        error = nil
        do {
            if let user = try await MeetupService.shared.findUserByPhone(e164) {
                if user.id == myId {
                    error = "That's you!"
                } else {
                    foundUser = user
                }
            } else {
                error = "No user found with that number"
            }
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    private func selectContact(_ contact: DeviceContact) async {
        isSearching = true
        contactSuggestions = []
        phoneSearch = ""
        foundUser = nil
        error = nil
        let myId = SupabaseManager.shared.client.auth.currentUser?.id
        var found: FoundUser?
        for phone in contact.phones {
            if let user = try? await MeetupService.shared.findUserByPhone(phone) { found = user; break }
        }
        if found == nil {
            for email in contact.emails {
                if let user = try? await MeetupService.shared.findUserByEmail(email) { found = user; break }
            }
        }
        if let user = found {
            if user.id == myId { error = "That's you!" }
            else { foundUser = user }
        } else {
            error = "\(contact.displayName) isn't on the app yet"
        }
        isSearching = false
    }

    private func addFriend(_ user: FoundUser) async {
        do {
            try await MeetupService.shared.addFriend(userId: user.id)
            phoneSearch = ""
            foundUser = nil
            error = "Friend request sent!"
            Task {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removePeople(at indices: IndexSet) async {
        for index in indices {
            let person = people[index]
            do {
                try await MeetupService.shared.removeFriend(userId: person.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
        await load()
    }
}
