import SwiftUI
import Supabase

struct MeetupsListView: View {
    @State private var participations: [MyParticipation] = []
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showCreate = false
    @State private var selectedMeetup: Meetup?
    @State private var deletedMeetupIds: Set<UUID> = []
    @State private var permanentlyHiddenIds: Set<UUID> = []
    @Environment(AuthViewModel.self) private var auth

    private var invited: [MyParticipation] {
        participations.filter { $0.status == "invited" && $0.meetup.status == "active" && !deletedMeetupIds.contains($0.meetup.id) && !permanentlyHiddenIds.contains($0.meetup.id) }
    }
    private var active: [MyParticipation] {
        participations.filter { $0.status != "invited" && $0.meetup.status == "active" && !deletedMeetupIds.contains($0.meetup.id) && !permanentlyHiddenIds.contains($0.meetup.id) }
    }
    private var past: [MyParticipation] {
        participations.filter { $0.meetup.status != "active" && $0.meetup.status != "cancelled" && !deletedMeetupIds.contains($0.meetup.id) && !permanentlyHiddenIds.contains($0.meetup.id) }
    }
    private var pastByCategory: [(key: String, value: [MyParticipation])] {
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
    private var deleted: [MyParticipation] {
        participations.filter { deletedMeetupIds.contains($0.meetup.id) && !permanentlyHiddenIds.contains($0.meetup.id) && $0.meetup.status != "cancelled" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else if invited.isEmpty && active.isEmpty && past.isEmpty && deleted.isEmpty {
                    ContentUnavailableView(
                        "No meetups yet",
                        systemImage: "map.circle",
                        description: Text("Tap + to create your first meetup.")
                    )
                } else {
                    List {
                        if !invited.isEmpty {
                            Section("Invited") {
                                ForEach(invited, id: \.meetup.id) { p in
                                    MeetupRow(participation: p)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedMeetup = p.meetup }
                                }
                                .onDelete { indices in Task { await deleteParticipations(invited, at: indices) } }
                            }
                        }
                        if !active.isEmpty {
                            Section("Active") {
                                ForEach(active, id: \.meetup.id) { p in
                                    MeetupRow(participation: p)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedMeetup = p.meetup }
                                }
                                .onDelete { indices in Task { await deleteParticipations(active, at: indices) } }
                            }
                        }
                        ForEach(pastByCategory, id: \.key) { group in
                            Section(group.key.isEmpty ? "Uncategorized" : group.key) {
                                ForEach(group.value, id: \.meetup.id) { p in
                                    MeetupRow(participation: p)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedMeetup = p.meetup }
                                }
                                .onDelete { indices in Task { await deleteParticipations(group.value, at: indices) } }
                            }
                        }
                        if !deleted.isEmpty {
                            Section("Recently Deleted") {
                                ForEach(deleted, id: \.meetup.id) { p in
                                    HStack {
                                        MeetupRow(participation: p)
                                        Spacer()
                                        Button("Restore") {
                                            restoreParticipation(p)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .onDelete { indices in
                                    for index in indices.sorted(by: >) {
                                        let id = deleted[index].meetup.id
                                        permanentlyHiddenIds.insert(id)
                                        deletedMeetupIds.remove(id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.3), value: hasLoaded)
            .navigationTitle("Meetups")
            .toolbar {
                Button("", systemImage: "plus") { showCreate = true }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                CreateMeetupView()
            }
            .sheet(item: $selectedMeetup) { meetup in
                MeetupDashboardView(meetup: meetup)
            }
            .task { loadHiddenIds(); if participations.isEmpty { await load() } }
            .refreshable { await load() }
            .onChange(of: deletedMeetupIds) { _, _ in saveHiddenIds() }
            .onChange(of: permanentlyHiddenIds) { _, _ in saveHiddenIds() }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func load() async {
        do {
            let result = try await MeetupService.shared.listMyParticipations()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                participations = result
                hasLoaded = true
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    private func deleteParticipations(_ array: [MyParticipation], at indices: IndexSet) async {
        for index in indices {
            let participation = array[index]
            deletedMeetupIds.insert(participation.meetup.id)
        }
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

struct MeetupRow: View {
    let participation: MyParticipation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(participation.meetup.destinationName)
                    .font(.headline)
                if let category = participation.meetup.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if let target = participation.meetup.targetArrivalAt {
                Text(target.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if participation.status == "invited" {
                Text("Pending your response")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
