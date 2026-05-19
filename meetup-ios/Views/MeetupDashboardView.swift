import SwiftUI
import MapKit
import Supabase

struct MeetupDashboardView: View {
    let meetup: Meetup
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @State private var participants: [MeetupParticipant] = []
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?
    @State private var showCancelConfirm = false
    @State private var showBill = false

    private var myUserId: UUID? { auth.session?.user.id }
    private var myStatus: String? { participants.first(where: { $0.userId == myUserId })?.status }
    private var destinationCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Map {
                        Marker(meetup.destinationName, coordinate: destinationCoord)
                            .tint(.red)
                        if meetup.status == "active" {
                            ForEach(participants) { p in
                                if let lat = p.lat, let lng = p.lng {
                                    Annotation(p.displayName ?? "?", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                        ParticipantPin(participant: p)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                    .disabled(true)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meetup.destinationName).font(.title2.bold())
                            if let addr = meetup.destinationAddress {
                                Text(addr).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let target = meetup.targetArrivalAt {
                                Label(
                                    target.formatted(date: .abbreviated, time: .shortened),
                                    systemImage: "clock"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            if let category = meetup.category, !category.isEmpty {
                                Text(category)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)

                        if myStatus == "invited" {
                            GlassEffectContainer(spacing: 12) {
                                HStack(spacing: 12) {
                                    Button("Decline") { Task { await respond(accept: false) } }
                                        .buttonStyle(.glass)
                                        .disabled(isActing)
                                    Button("Accept") { Task { await respond(accept: true) } }
                                        .buttonStyle(.glassProminent)
                                        .disabled(isActing)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("People")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            if !hasLoaded {
                                ProgressView().padding()
                            } else {
                                ForEach(participants) { p in
                                    ParticipantTile(participant: p, isMe: p.userId == myUserId, targetArrivalAt: meetup.targetArrivalAt)
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }

                        Button {
                            let url = URL(string: "http://maps.apple.com/?daddr=\(meetup.destinationLat),\(meetup.destinationLng)&dirflg=d")!
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Open in Apple Maps", systemImage: "map.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        Button {
                            showBill = true
                        } label: {
                            Label("Split Bill", systemImage: "receipt")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(meetup.destinationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if myUserId == meetup.hostId {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Cancel Meetup", role: .destructive) {
                            showCancelConfirm = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showBill) {
                BillView(meetup: meetup, participants: participants)
                    .environment(auth)
            }
            .confirmationDialog("Cancel this meetup?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("Cancel Meetup", role: .destructive) {
                    Task {
                        try? await MeetupService.shared.cancelMeetup(meetupId: meetup.id)
                        dismiss()
                    }
                }
                Button("Keep Meetup", role: .cancel) {}
            }
            .task {
                await load()
                await startRealtime()
            }
            .onDisappear {
                LocationManager.shared.stopTracking()
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func startRealtime() async {
        let channel = SupabaseManager.shared.client.realtimeV2.channel("meetup-\(meetup.id)")
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

    private func load() async {
        do {
            let fresh = try await MeetupService.shared.listParticipants(meetupId: meetup.id)
            if fresh != participants { participants = fresh }
            if myStatus == "accepted" && meetup.status == "active" {
                LocationManager.shared.requestPermission()
                LocationManager.shared.startTracking(meetup: meetup)
            }
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    private func respond(accept: Bool) async {
        isActing = true
        do {
            if accept {
                try await MeetupService.shared.accept(meetupId: meetup.id)
            } else {
                try await MeetupService.shared.decline(meetupId: meetup.id)
            }
            await load()
        } catch {
            self.error = error.localizedDescription
        }
        isActing = false
    }
}

struct ParticipantPin: View {
    let participant: MeetupParticipant

    private var color: Color {
        switch participant.status {
        case "accepted": return .green
        case "declined": return .red
        case "arrived":  return .blue
        default:         return .orange
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay {
                Text(String((participant.displayName ?? "?").prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .shadow(radius: 2)
    }
}

struct ParticipantTile: View {
    let participant: MeetupParticipant
    let isMe: Bool
    let targetArrivalAt: Date?

    private var statusColor: Color {
        switch participant.status {
        case "accepted": return .green
        case "declined": return .red
        case "arrived":  return .blue
        default:         return .orange
        }
    }

    private var statusLabel: String {
        switch participant.status {
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "arrived":  return "Arrived"
        default:         return "Invited"
        }
    }

    private var etaLabel: String? {
        guard let seconds = participant.etaSeconds, participant.status == "accepted" else { return nil }
        let minutes = seconds / 60
        if minutes < 1 { return "Almost there" }
        if minutes < 60 { return "\(minutes) min away" }
        return "\(minutes / 60)h \(minutes % 60)m away"
    }

    private var lateLabel: String? {
        guard let target = targetArrivalAt,
              let seconds = participant.etaSeconds,
              participant.status == "accepted" else { return nil }
        let eta = Date().addingTimeInterval(TimeInterval(seconds))
        guard eta > target else { return nil }
        let lateBy = Int(eta.timeIntervalSince(target)) / 60
        return "\(lateBy) min late"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String((participant.displayName ?? "?").prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(statusColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(participant.displayName ?? "Unknown")
                    if isMe {
                        Text("(you)").foregroundStyle(.secondary).font(.subheadline)
                    }
                }
                if let late = lateLabel {
                    Text(late)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let eta = etaLabel {
                    Text(eta)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
