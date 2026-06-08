import SwiftUI
import Supabase

func meetupCategoryGradient(category: String?, meetupStatus: String, participantStatus: String) -> AnyShapeStyle {
    let isActive = meetupStatus == "active"
    let isInvited = participantStatus == "invited"
    guard isActive && !isInvited else {
        return AnyShapeStyle(Color.appSurface)
    }
    let c = (category ?? "").lowercased()
    if c.contains("brunch") || c.contains("dinner") || c.contains("food") || c.contains("lunch") {
        return AnyShapeStyle(LinearGradient(
            colors: [Color.categoryGradientFoodStart,
                     Color.categoryGradientFoodEnd],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    if c.contains("happy hour") || c.contains("cocktail") || c.contains("drink") {
        return AnyShapeStyle(LinearGradient(
            colors: [Color(red: 0.361, green: 0.247, blue: 0.627),
                     Color(red: 0.239, green: 0.141, blue: 0.439)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    if c.contains("coffee") || c.contains("café") || c.contains("cafe") {
        return AnyShapeStyle(LinearGradient(
            colors: [Color(red: 0.090, green: 0.376, blue: 0.208),
                     Color(red: 0.047, green: 0.239, blue: 0.125)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    return AnyShapeStyle(Color.appSurface)
}

func meetupHasDarkBackground(category: String?, meetupStatus: String, participantStatus: String) -> Bool {
    let isActive = meetupStatus == "active"
    let isInvited = participantStatus == "invited"
    guard isActive && !isInvited else { return false }
    let c = (category ?? "").lowercased()
    return c.contains("brunch") || c.contains("dinner") || c.contains("food") || c.contains("lunch") ||
           c.contains("happy hour") || c.contains("cocktail") || c.contains("drink") ||
           c.contains("coffee") || c.contains("café") || c.contains("cafe")
}

func meetupCategoryEmoji(_ category: String?) -> String {
    let c = (category ?? "").lowercased()
    if c.contains("brunch")                               { return "🍳" }
    if c.contains("happy hour") || c.contains("cocktail") { return "🍸" }
    if c.contains("dinner") || c.contains("food") || c.contains("lunch") { return "🍽️" }
    if c.contains("coffee") || c.contains("café") || c.contains("cafe")  { return "☕" }
    if c.contains("kickback") || c.contains("hangout")    { return "🎉" }
    if c.contains("drink") || c.contains("bar")           { return "🍺" }
    return "📍"
}

// MARK: - Meetups List

struct MeetupsListView: View {
    @State private var participations: [MyParticipation] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var selectedMeetup: Meetup?
    @State private var selectedRecap: MyParticipation?
    @State private var deletedMeetupIds: Set<UUID> = []
    @State private var permanentlyHiddenIds: Set<UUID> = []
    // Memoized: dictionary-group + sort runs only when participations/hidden sets change.
    @State private var cachedPastByCategory: [(key: String, value: [MyParticipation])] = []
    @Environment(AuthViewModel.self) private var auth
    @Environment(NavigationState.self) private var navState

    private func isVisible(_ p: MyParticipation) -> Bool {
        !deletedMeetupIds.contains(p.meetup.id) && !permanentlyHiddenIds.contains(p.meetup.id)
    }

    private var invited: [MyParticipation] {
        participations.filter { isVisible($0) && $0.status == "invited" && $0.meetup.status == "active" }
    }
    private func isExpired(_ p: MyParticipation) -> Bool {
        p.meetup.endsAt.addingTimeInterval(2 * 3600) < Date()
    }
    private var active: [MyParticipation] {
        participations.filter { isVisible($0) && $0.status != "invited" && $0.meetup.status == "active" && !isExpired($0) }
    }
    private var past: [MyParticipation] {
        participations.filter {
            isVisible($0) &&
            (($0.meetup.status != "active" && $0.meetup.status != "cancelled") ||
             ($0.meetup.status == "active" && isExpired($0)))
        }
    }
    private var deleted: [MyParticipation] {
        participations.filter {
            deletedMeetupIds.contains($0.meetup.id) &&
            !permanentlyHiddenIds.contains($0.meetup.id) &&
            $0.meetup.status != "cancelled"
        }
    }

    private func buildPastByCategory() -> [(key: String, value: [MyParticipation])] {
        let grouped = Dictionary(grouping: past) { $0.meetup.category ?? "" }
        return grouped
            .sorted { a, b in
                if a.key.isEmpty { return false }
                if b.key.isEmpty { return true }
                let aLatest = a.value.compactMap { $0.meetup.targetArrivalAt }.max() ?? .distantPast
                let bLatest = b.value.compactMap { $0.meetup.targetArrivalAt }.max() ?? .distantPast
                return aLatest > bLatest
            }
            .map { key, value in
                let sorted = value.sorted {
                    ($0.meetup.targetArrivalAt ?? $0.meetup.createdAt) >
                    ($1.meetup.targetArrivalAt ?? $1.meetup.createdAt)
                }
                return (key: key, value: sorted)
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                        .tint(Color.coral)
                } else if invited.isEmpty && active.isEmpty && past.isEmpty && deleted.isEmpty {
                    MeetupsEmptyState { showCreate = true }
                } else {
                    meetupsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .animation(.easeOut(duration: 0.3), value: hasLoaded)
            .navigationTitle("Meetups")
            .toolbar {
                Button(action: { showCreate = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.coral)
                        .clipShape(Circle())
                        .shadow(color: Color.coral.opacity(0.4), radius: 6, y: 3)
                }
                .accessibilityLabel("Create Meetup")
                .accessibilityIdentifier("btn_create_meetup")
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                CreateMeetupView()
            }
            .sheet(item: $selectedMeetup) { meetup in
                MeetupDashboardView(meetup: meetup)
            }
            .sheet(item: $selectedRecap) { p in
                RecapView(meetup: p.meetup)
                    .environment(auth)
            }
            .task {
                loadHiddenIds()
                await load()
                await subscribeToInviteChanges()
            }
            .refreshable { await load() }
            .onChange(of: deletedMeetupIds) { _, _ in saveHiddenIds(); cachedPastByCategory = buildPastByCategory() }
            .onChange(of: permanentlyHiddenIds) { _, _ in saveHiddenIds(); cachedPastByCategory = buildPastByCategory() }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .preferredColorScheme(.dark)
            .onChange(of: navState.pendingMeetupId) { _, meetupId in
                handlePendingMeetupId(meetupId)
            }
        }
    }

    private var meetupsList: some View {
        List {
            Color.clear.frame(height: 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if !invited.isEmpty {
                Section {
                    ForEach(invited, id: \.meetup.id) { p in
                        RSVPInviteCard(
                            participation: p,
                            onOpen: { selectedMeetup = p.meetup },
                            onRespond: { status in await rsvp(p, status: status) }
                        )
                        .accessibilityLabel("RSVP to \(p.meetup.destinationName)")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .onDelete { indices in Task { await deleteParticipations(invited, at: indices) } }
                } header: {
                    HStack(spacing: 6) {
                        sectionHeader("Invited")
                        Text("\(invited.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.coral)
                            .clipShape(Capsule())
                    }
                }
                .listSectionSeparator(.hidden)
            }

            if !active.isEmpty {
                Section {
                    ForEach(active, id: \.meetup.id) { p in
                        Button { selectedMeetup = p.meetup } label: {
                            MeetupRowCard(participation: p)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(p.meetup.destinationName)")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .onDelete { indices in Task { await deleteParticipations(active, at: indices) } }
                } header: {
                    sectionHeader("Active")
                }
                .listSectionSeparator(.hidden)
            }

            ForEach(cachedPastByCategory, id: \.key) { group in
                Section {
                    ForEach(group.value, id: \.meetup.id) { p in
                        Button {
                            if p.meetup.isRecap {
                                selectedRecap = p
                            } else {
                                selectedMeetup = p.meetup
                            }
                        } label: {
                            MeetupRowCard(participation: p)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(p.meetup.destinationName)")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .onDelete { indices in Task { await deleteParticipations(group.value, at: indices) } }
                } header: {
                    sectionHeader(group.key.isEmpty ? "Past" : group.key)
                }
                .listSectionSeparator(.hidden)
            }

            if !deleted.isEmpty {
                Section {
                    ForEach(deleted, id: \.meetup.id) { p in
                        HStack {
                            MeetupRowCard(participation: p)
                            Spacer()
                            Button("Restore") { restoreParticipation(p) }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.coral)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .onDelete { indices in
                        for index in indices.sorted(by: >) {
                            let id = deleted[index].meetup.id
                            permanentlyHiddenIds.insert(id)
                            deletedMeetupIds.remove(id)
                        }
                    }
                } header: {
                    sectionHeader("Recently Deleted")
                }
                .listSectionSeparator(.hidden)
            }

            Color.clear.frame(height: 24)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            if title == "Active" || title == "Invited" {
                Circle()
                    .fill(title == "Active" ? Color.statusLive : Color.statusPending)
                    .frame(width: 6, height: 6)
                    .shadow(color: (title == "Active" ? Color.statusLive : Color.statusPending).opacity(0.8), radius: 4)
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(white: 0.45))
                .textCase(nil)
        }
        .padding(.leading, 4)
        .padding(.top, 8)
    }

    private func handlePendingMeetupId(_ meetupId: UUID?) {
        guard let meetupId else { return }
        navState.pendingMeetupId = nil
        var found: MyParticipation?
        for p in participations where p.meetup.id == meetupId { found = p; break }
        if let p = found {
            selectedMeetup = p.meetup
        } else {
            Task {
                await load()
                for p in participations where p.meetup.id == meetupId {
                    selectedMeetup = p.meetup
                    break
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            let result = try await MeetupService.shared.listMyParticipations()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                if result != participations { participations = result }
                hasLoaded = true
            }
            cachedPastByCategory = buildPastByCategory()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    private func rsvp(_ participation: MyParticipation, status: String) async {
        do {
            switch status {
            case "yes":   try await MeetupService.shared.accept(meetupId: participation.meetup.id)
            case "no":    try await MeetupService.shared.decline(meetupId: participation.meetup.id)
            case "maybe": try await MeetupService.shared.maybe(meetupId: participation.meetup.id)
            default: break
            }
            await load()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func subscribeToInviteChanges() async {
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        let channel = SupabaseManager.shared.client.realtimeV2.channel("my-participations-\(userId)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "meetup_participants")
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await load()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }

    private func deleteParticipations(_ array: [MyParticipation], at indices: IndexSet) async {
        for index in indices { deletedMeetupIds.insert(array[index].meetup.id) }
    }

    private func loadHiddenIds() {
        if let raw = UserDefaults.standard.stringArray(forKey: "deletedMeetupIds") {
            deletedMeetupIds = Set(raw.compactMap { UUID(uuidString: $0) })
        }
        if let raw = UserDefaults.standard.stringArray(forKey: "permanentlyHiddenIds") {
            permanentlyHiddenIds = Set(raw.compactMap { UUID(uuidString: $0) })
        }
    }

    private func saveHiddenIds() {
        UserDefaults.standard.set(deletedMeetupIds.map { $0.uuidString }, forKey: "deletedMeetupIds")
        UserDefaults.standard.set(permanentlyHiddenIds.map { $0.uuidString }, forKey: "permanentlyHiddenIds")
    }

    private func restoreParticipation(_ participation: MyParticipation) {
        deletedMeetupIds.remove(participation.meetup.id)
    }
}

// MARK: - Empty State

private struct MeetupsEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RadialGradient(
                    colors: [Color.coral.opacity(0.12), Color.clear],
                    center: .center, startRadius: 0, endRadius: 70
                )
                .frame(width: 140, height: 140)

                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.coral.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(Color.coral.opacity(0.25), lineWidth: 1.5)
                        )
                        .frame(width: 72, height: 72)

                    Text("📍")
                        .font(.system(size: 32))
                        .frame(width: 72, height: 72)

                    Text("✨")
                        .font(.system(size: 14))
                        .offset(x: 8, y: -8)
                }
            }

            VStack(spacing: 8) {
                Text("No meetups yet")
                    .font(.system(size: 18, weight: .bold))

                Text("Gather your crew and plan something fun.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Plan a Meetup", action: onCreate)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.coral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.coral.opacity(0.4), radius: 8, y: 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

// MARK: - Row Card

struct MeetupRowCard: View {
    let participation: MyParticipation

    private var needsBorder: Bool {
        participation.meetup.status != "active" || participation.status == "invited"
    }

    private var hasDarkBackground: Bool {
        meetupHasDarkBackground(
            category: participation.meetup.category,
            meetupStatus: participation.meetup.status,
            participantStatus: participation.status
        )
    }

    private var primaryTextColor: Color { .white }

    private var secondaryTextColor: Color {
        hasDarkBackground ? .white.opacity(0.5) : Color(white: 0.55)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(meetupCategoryEmoji(participation.meetup.category))
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 2) {
                Text(participation.meetup.destinationName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                if let addr = participation.meetup.destinationAddress, !addr.isEmpty {
                    Text(addr)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                if let target = participation.meetup.targetArrivalAt {
                    Text(target, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }
                MeetupStatusPill(participation: participation)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(meetupCategoryGradient(
                    category: participation.meetup.category,
                    meetupStatus: participation.meetup.status,
                    participantStatus: participation.status
                ))
            if !needsBorder && participation.meetup.status == "active" {
                // Glowing accent border for active meetups
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.coral.opacity(0.45), lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(white: 0.15), lineWidth: 1)
            }
        }
        .shadow(
            color: participation.meetup.status == "active" ? Color.coral.opacity(0.12) : Color.clear,
            radius: 10, y: 4
        )
        .opacity(participation.meetup.status != "active" ? 0.50 : 1.0)
    }
}

// MARK: - Status Pill

private struct MeetupStatusPill: View {
    let participation: MyParticipation

    private var config: (text: String, fg: Color, bg: Color)? {
        guard participation.meetup.status == "active" else { return nil }
        guard participation.status != "arrived" else { return nil }

        if participation.status == "invited" {
            let c = Color.statusPending
            return ("Invited", c, c.opacity(0.2))
        }
        if participation.status == "maybe" {
            let c = Color.statusPending
            return ("Maybe", c, c.opacity(0.2))
        }
        if participation.status == "no" || participation.status == "declined" {
            let c = Color.statusLate
            return ("No", c, c.opacity(0.2))
        }
        if let target = participation.meetup.targetArrivalAt, Date() > target {
            let c = Color.statusLate
            return ("Late", c, c.opacity(0.2))
        }
        let c = Color.statusLive
        return ("Live", c, c.opacity(0.2))
    }

    var body: some View {
        if let c = config {
            Text(c.text)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(c.fg)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(c.bg)
                .clipShape(Capsule())
        }
    }
}
