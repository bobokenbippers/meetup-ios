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

private enum MeetupsSheet: Identifiable {
    case create
    case meetup(Meetup)
    case recap(MyParticipation)
    case recapFolder

    var id: String {
        switch self {
        case .create:
            return "create"
        case .meetup(let meetup):
            return "meetup-\(meetup.id)"
        case .recap(let participation):
            return "recap-\(participation.meetup.id)"
        case .recapFolder:
            return "recap-folder"
        }
    }
}

enum MeetupListFilters {
    static func eventSortDate(_ meetup: Meetup) -> Date {
        meetup.targetArrivalAt ?? meetup.startsAt
    }

    static func isExpired(_ participation: MyParticipation, now: Date = Date()) -> Bool {
        let meetup = participation.meetup
        if let target = meetup.targetArrivalAt {
            return now > target.addingTimeInterval(1.5 * 3600)
        }
        return meetup.endsAt < now || now > meetup.createdAt.addingTimeInterval(6 * 3600)
    }

    static func invited(
        _ participations: [MyParticipation],
        deletedMeetupIds: Set<UUID> = [],
        permanentlyHiddenIds: Set<UUID> = [],
        now: Date = Date()
    ) -> [MyParticipation] {
        participations
            .filter {
                isVisible($0, deletedMeetupIds: deletedMeetupIds, permanentlyHiddenIds: permanentlyHiddenIds) &&
                $0.status == "invited" &&
                $0.meetup.status == "active" &&
                !isExpired($0, now: now)
            }
            .sorted { eventSortDate($0.meetup) < eventSortDate($1.meetup) }
    }

    static func active(
        _ participations: [MyParticipation],
        deletedMeetupIds: Set<UUID> = [],
        permanentlyHiddenIds: Set<UUID> = [],
        now: Date = Date()
    ) -> [MyParticipation] {
        participations
            .filter {
                isVisible($0, deletedMeetupIds: deletedMeetupIds, permanentlyHiddenIds: permanentlyHiddenIds) &&
                $0.status != "invited" &&
                $0.meetup.status == "active" &&
                !isExpired($0, now: now)
            }
            .sorted { eventSortDate($0.meetup) < eventSortDate($1.meetup) }
    }

    static func past(
        _ participations: [MyParticipation],
        deletedMeetupIds: Set<UUID> = [],
        permanentlyHiddenIds: Set<UUID> = [],
        now: Date = Date()
    ) -> [MyParticipation] {
        participations.filter {
            isVisible($0, deletedMeetupIds: deletedMeetupIds, permanentlyHiddenIds: permanentlyHiddenIds) &&
            (($0.meetup.status != "active" && $0.meetup.status != "cancelled") ||
             ($0.meetup.status == "active" && isExpired($0, now: now)))
        }
    }

    static func pastByCategory(_ past: [MyParticipation]) -> [(key: String, value: [MyParticipation])] {
        let grouped = Dictionary(grouping: past) { $0.meetup.category ?? "" }
        return grouped
            .sorted { a, b in
                if a.key.isEmpty { return false }
                if b.key.isEmpty { return true }
                let aLatest = a.value.map { eventSortDate($0.meetup) }.max() ?? .distantPast
                let bLatest = b.value.map { eventSortDate($0.meetup) }.max() ?? .distantPast
                return aLatest > bLatest
            }
            .map { key, value in
                let sorted = value.sorted {
                    eventSortDate($0.meetup) > eventSortDate($1.meetup)
                }
                return (key: key, value: sorted)
            }
    }

    private static func isVisible(
        _ participation: MyParticipation,
        deletedMeetupIds: Set<UUID>,
        permanentlyHiddenIds: Set<UUID>
    ) -> Bool {
        !deletedMeetupIds.contains(participation.meetup.id) &&
        !permanentlyHiddenIds.contains(participation.meetup.id)
    }
}

struct MeetupsListView: View {
    @State private var participations: [MyParticipation] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var eventPrefill: EventPrefill?
    @State private var presentedSheet: MeetupsSheet?
    @State private var deletedMeetupIds: Set<UUID> = []
    @State private var permanentlyHiddenIds: Set<UUID> = []
    @Environment(AuthViewModel.self) private var auth
    @Environment(NavigationState.self) private var navState

    private var invited: [MyParticipation] {
        MeetupListFilters.invited(
            participations,
            deletedMeetupIds: deletedMeetupIds,
            permanentlyHiddenIds: permanentlyHiddenIds
        )
    }

    private var active: [MyParticipation] {
        MeetupListFilters.active(
            participations,
            deletedMeetupIds: deletedMeetupIds,
            permanentlyHiddenIds: permanentlyHiddenIds
        )
    }

    private var past: [MyParticipation] {
        MeetupListFilters.past(
            participations,
            deletedMeetupIds: deletedMeetupIds,
            permanentlyHiddenIds: permanentlyHiddenIds
        )
    }

    private var deleted: [MyParticipation] {
        participations.filter {
            deletedMeetupIds.contains($0.meetup.id) &&
            !permanentlyHiddenIds.contains($0.meetup.id) &&
            $0.meetup.status != "cancelled"
        }
    }

    private var liveMeetupsForCreate: [Meetup] {
        (invited + active).map(\.meetup)
    }

    private var pastByCategory: [(key: String, value: [MyParticipation])] {
        MeetupListFilters.pastByCategory(past)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                        .tint(Color.coral)
                } else if invited.isEmpty && active.isEmpty && past.isEmpty && deleted.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            NearbyEventsView(onSelect: openCreate(prefill:))
                            MeetupsEmptyState { presentedSheet = .create }
                                .frame(minHeight: 480)
                        }
                    }
                } else {
                    meetupsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .animation(.easeOut(duration: 0.3), value: hasLoaded)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(action: { presentedSheet = .create }) {
                    Image(systemName: "plus")
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.coral)
                        .clipShape(Circle())
                        .shadow(color: Color.coral.opacity(0.4), radius: 6, y: 3)
                }
                .accessibilityLabel("Create Meetup")
                .accessibilityIdentifier("btn_create_meetup")
            }
            .sheet(item: $presentedSheet, onDismiss: handleSheetDismiss) { sheet in
                switch sheet {
                case .create:
                    CreateMeetupView(prefill: eventPrefill, liveMeetups: liveMeetupsForCreate)
                case .meetup(let meetup):
                    MeetupDashboardView(meetup: meetup)
                case .recap(let participation):
                    RecapView(meetup: participation.meetup)
                        .environment(auth)
                case .recapFolder:
                    RecapFolderView(groups: pastByCategory) { participation in
                        presentedSheet = .recap(participation)
                    }
                }
            }
            .task {
                loadHiddenIds()
                await load()
                await subscribeToInviteChanges()
            }
            .refreshable { await load() }
            .onChange(of: deletedMeetupIds) { _, _ in saveHiddenIds() }
            .onChange(of: permanentlyHiddenIds) { _, _ in saveHiddenIds() }
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
            Text("Meetups")
                .scaledFont(size: 34, weight: .bold)
                .foregroundStyle(.white)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

            NearbyEventsView(onSelect: openCreate(prefill:))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

            if !invited.isEmpty {
                Section {
                    ForEach(invited, id: \.meetup.id) { p in
                        RSVPInviteCard(
                            participation: p,
                            onOpen: { presentedSheet = .meetup(p.meetup) },
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
                            .scaledFont(size: 10, weight: .bold)
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
                        Button { presentedSheet = .meetup(p.meetup) } label: {
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

            if !past.isEmpty {
                Section {
                    Button { presentedSheet = .recapFolder } label: {
                        RecapFolderCard(recapCount: past.count, latestMeetup: past.sorted {
                            MeetupListFilters.eventSortDate($0.meetup) > MeetupListFilters.eventSortDate($1.meetup)
                        }.first?.meetup)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open recaps")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            for participation in past {
                                deletedMeetupIds.insert(participation.meetup.id)
                            }
                        } label: {
                            Label("Hide", systemImage: "archivebox")
                        }
                    }
                } header: {
                    sectionHeader("Recaps")
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
                        .buttonStyle(.plain)
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
        .contentMargins(.top, 0, for: .scrollContent)
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
                .scaledFont(size: 10, weight: .bold)
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
            presentedSheet = .meetup(p.meetup)
        } else {
            Task {
                await load()
                for p in participations where p.meetup.id == meetupId {
                    presentedSheet = .meetup(p.meetup)
                    break
                }
            }
        }
    }

    private func openCreate(prefill: EventPrefill) {
        eventPrefill = prefill
        presentedSheet = .create
    }

    private func handleSheetDismiss() {
        eventPrefill = nil
        Task { await load() }
    }

    // MARK: - Data

    private func load() async {
        do {
            let result = try await MeetupService.shared.listMyParticipations()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                if result != participations { participations = result }
                hasLoaded = true
            }
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
                        .scaledFont(size: 32)
                        .frame(width: 72, height: 72)

                    Text("✨")
                        .scaledFont(size: 14)
                        .offset(x: 8, y: -8)
                }
            }

            VStack(spacing: 8) {
                Text("No meetups yet")
                    .scaledFont(size: 18, weight: .bold)

                Text("Gather your crew and plan something fun.")
                    .scaledFont(size: 12)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Plan a Meetup", action: onCreate)
                .scaledFont(size: 14, weight: .bold)
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

// MARK: - Recap Folder

private struct RecapFolderCard: View {
    let recapCount: Int
    let latestMeetup: Meetup?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.coral.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "folder.fill")
                    .scaledFont(size: 23, weight: .semibold)
                    .foregroundStyle(Color.coral)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Recaps")
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(.white)
                if let latestMeetup {
                    Text("Latest: \(latestMeetup.destinationName)")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color(white: 0.58))
                        .lineLimit(1)
                } else {
                    Text("Past meetups")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color(white: 0.58))
                }
            }

            Spacer()

            Text("\(recapCount)")
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.appSurface)
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color(white: 0.36))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(white: 0.15), lineWidth: 1)
        )
    }
}

private struct RecapFolderView: View {
    let groups: [(key: String, value: [MyParticipation])]
    let onSelect: (MyParticipation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("Recaps")
                    .scaledFont(size: 34, weight: .bold)
                    .foregroundStyle(.white)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

                ForEach(groups, id: \.key) { group in
                    Section {
                        ForEach(group.value, id: \.meetup.id) { participation in
                            Button {
                                onSelect(participation)
                            } label: {
                                MeetupRowCard(participation: participation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open recap for \(participation.meetup.destinationName)")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    } header: {
                        HStack(spacing: 6) {
                            sectionHeader(group.key.isEmpty ? "Past" : group.key)
                            Text("\(group.value.count)")
                                .scaledFont(size: 10, weight: .bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appSurface)
                                .clipShape(Capsule())
                        }
                    }
                    .listSectionSeparator(.hidden)
                }

                Color.clear.frame(height: 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .scaledFont(size: 10, weight: .bold)
            .foregroundStyle(Color(white: 0.45))
            .textCase(nil)
            .padding(.leading, 4)
            .padding(.top, 8)
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
                .scaledFont(size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(participation.meetup.destinationName)
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                if let addr = participation.meetup.destinationAddress, !addr.isEmpty {
                    Text(addr)
                        .scaledFont(size: 11)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                if let target = participation.meetup.targetArrivalAt {
                    Text(target, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .scaledFont(size: 10, weight: .medium)
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
                .scaledFont(size: 9, weight: .bold)
                .foregroundStyle(c.fg)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(c.bg)
                .clipShape(Capsule())
        }
    }
}
