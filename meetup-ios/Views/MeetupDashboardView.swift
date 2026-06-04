import SwiftUI
import MapKit
import Supabase

struct MeetupDashboardView: View {
    let meetup: Meetup
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @Environment(AppSettings.self) private var settings

    @State private var participants: [MeetupParticipant] = []
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?
    @State private var showCancelConfirm = false
    @State private var showBill = false
    @State private var showConfetti = false

    private var myUserId: UUID? { auth.session?.user.id }
    private var myStatus: String? { participants.first(where: { $0.userId == myUserId })?.status }
    private var destinationCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
    }
    private var acceptedCount: Int {
        participants.filter { $0.status == "accepted" || $0.status == "arrived" }.count
    }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                dashboardHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                // Destination card
                destinationCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                // Map — full-bleed, fills remaining space
                Map {
                    Annotation("", coordinate: destinationCoord) {
                        DestinationMarker()
                    }
                    if meetup.status == "active" {
                        ForEach(participants) { p in
                            if let lat = p.lat, let lng = p.lng {
                                Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                    DashboardParticipantPin(
                                        participant: p,
                                        isMe: p.userId == myUserId,
                                        targetArrivalAt: meetup.targetArrivalAt
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .disabled(true)

                // Bottom panel
                bottomPanel
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if myUserId == meetup.hostId {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Cancel", role: .destructive) { showCancelConfirm = true }
                    }
                }
            }
            .sheet(isPresented: $showBill) {
                BillView(meetup: meetup, participants: participants)
                    .environment(auth)
                    .environment(settings)
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
            .overlay {
                if showConfetti { ConfettiView() }
            }
        }
    }

    // MARK: - Sub-views

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(greeting), \(auth.profile?.displayName ?? "there") 👋")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(meetup.destinationName)
                .font(.system(size: 24, weight: .black))
                .lineLimit(1)
            Text("You're meeting \(acceptedCount) \(acceptedCount == 1 ? "person" : "people")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.coral)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(meetup.destinationName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if let addr = meetup.destinationAddress {
                    Text(addr)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let target = meetup.targetArrivalAt {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(target, format: .dateTime.hour().minute())
                        .font(.system(size: 13, weight: .bold))
                    let mins = Int(target.timeIntervalSinceNow / 60)
                    if mins > 0 {
                        Text("in \(mins) min")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.18))
                .frame(width: 32, height: 3)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // "Everyone" label
            Text("Everyone")
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Participant rows
            if hasLoaded {
                VStack(spacing: 0) {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                        DashboardParticipantRow(
                            participant: p,
                            isMe: p.userId == myUserId,
                            targetArrivalAt: meetup.targetArrivalAt
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.8).delay(Double(idx) * 0.05),
                            value: hasLoaded
                        )
                        if idx < participants.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.bottom, 8)
            } else {
                ProgressView().padding()
            }

            // Accept / Decline
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
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    openDirections()
                } label: {
                    Label("Directions", systemImage: "map.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button { showBill = true } label: {
                    Label("Split Bill", systemImage: "receipt").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, topTrailing: 22)))
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, topTrailing: 22))
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: myStatus)
    }

    // MARK: - Logic

    private func openDirections() {
        let lat = meetup.destinationLat
        let lng = meetup.destinationLng
        let gmNative = URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=driving")!
        if UIApplication.shared.canOpenURL(gmNative) {
            UIApplication.shared.open(gmNative)
        } else {
            let gmWeb = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)&travelmode=driving")!
            UIApplication.shared.open(gmWeb)
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                if fresh != participants { participants = fresh }
                hasLoaded = true
            }
            if myStatus == "accepted" && meetup.status == "active" {
                LocationManager.shared.requestPermission()
                LocationManager.shared.startTracking(meetup: meetup)
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    private func respond(accept: Bool) async {
        isActing = true
        do {
            if accept {
                try await MeetupService.shared.accept(meetupId: meetup.id)
                withAnimation { showConfetti = true }
                Task {
                    do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
                    showConfetti = false
                }
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

// MARK: - Destination Marker

private struct DestinationMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.coral.opacity(0.2))
                .frame(width: 44, height: 44)
            Circle()
                .fill(Color.coral)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: Color.coral.opacity(0.6), radius: 6)
        }
    }
}

// MARK: - Participant Pin (on map)

struct DashboardParticipantPin: View {
    let participant: MeetupParticipant
    let isMe: Bool
    let targetArrivalAt: Date?

    private var etaText: String {
        if participant.status == "arrived" { return "✓ Here" }
        if let late = participant.lateLabel(target: targetArrivalAt) { return late }
        return participant.etaLabel() ?? participant.status.capitalized
    }

    private var etaColor: Color {
        if participant.status == "arrived" { return .secondary }
        if participant.lateLabel(target: targetArrivalAt) != nil { return Color(red: 1, green: 0.294, blue: 0.294) }
        return Color(red: 0.180, green: 0.835, blue: 0.451)
    }

    private var avatarColor: Color {
        pinColor(for: participant.userId)
    }

    var body: some View {
        if isMe {
            // Blue pulsing "You" dot
            ZStack {
                Circle()
                    .fill(Color(red: 0.118, green: 0.565, blue: 1.0).opacity(0.25))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(Color(red: 0.118, green: 0.565, blue: 1.0))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: Color(red: 0.118, green: 0.565, blue: 1.0).opacity(0.6), radius: 4)
            }
        } else {
            HStack(spacing: 4) {
                // Avatar circle
                Circle()
                    .fill(avatarColor)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .overlay {
                        Text(String((participant.displayName ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(radius: 3)

                // Callout bubble
                VStack(alignment: .leading, spacing: 1) {
                    Text(participant.displayName ?? "?")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(etaText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(etaColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }
}

private func pinColor(for userId: UUID) -> Color {
    let palette: [Color] = [
        Color(red: 0.910, green: 0.361, blue: 0.016),
        Color(red: 0.482, green: 0.361, blue: 0.749),
        Color(red: 0.118, green: 0.565, blue: 1.000),
        Color(red: 0.180, green: 0.800, blue: 0.443),
        Color(red: 0.910, green: 0.212, blue: 0.278),
        Color(red: 0.000, green: 0.780, blue: 0.941),
    ]
    return palette[abs(userId.hashValue) % palette.count]
}

// MARK: - Participant Row (in bottom panel)

private struct DashboardParticipantRow: View {
    let participant: MeetupParticipant
    let isMe: Bool
    let targetArrivalAt: Date?

    private var etaText: String {
        if participant.status == "arrived" { return "✓ Here" }
        if let late = participant.lateLabel(target: targetArrivalAt) { return late }
        return participant.etaLabel() ?? participant.status.capitalized
    }

    private var etaColor: Color {
        if participant.status == "arrived" { return .secondary }
        if participant.lateLabel(target: targetArrivalAt) != nil { return Color(red: 1, green: 0.294, blue: 0.294) }
        if participant.status == "invited"  { return Color(red: 1, green: 0.839, blue: 0) }
        if participant.status == "declined" { return .secondary }
        return Color(red: 0.180, green: 0.835, blue: 0.451)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(pinColor(for: participant.userId).opacity(0.8))
                .frame(width: 30, height: 30)
                .overlay {
                    Text(String((participant.displayName ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(participant.displayName ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                    if isMe {
                        Text("(you)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(etaText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(etaColor)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Confetti

private struct ConfettiView: View {
    @Environment(AppSettings.self) private var settings

    private struct Particle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let color: Color
        let width: CGFloat
        let height: CGFloat
        let delay: Double
        let duration: Double
        let drift: CGFloat
        let startAngle: Double
        let endAngle: Double
    }

    @State private var particles: [Particle] = {
        let palette: [Color] = [.pink, .purple, .blue, .orange, .yellow, .green, .red, .cyan, .mint, .indigo]
        return (0..<60).map { _ in
            Particle(
                x: .random(in: 0.05...0.95),
                color: palette.randomElement()!,
                width: .random(in: 6...12),
                height: .random(in: 4...8),
                delay: .random(in: 0...0.55),
                duration: .random(in: 1.3...2.1),
                drift: .random(in: -80...80),
                startAngle: .random(in: -20...20),
                endAngle: .random(in: 220...560)
            )
        }
    }()

    @State private var drop = false
    @State private var opacity: Double = 1

    var body: some View {
        if settings.reduceMotion {
            // Reduce motion: simple fade flash instead of falling particles
            Color.white
                .opacity(opacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) { opacity = 0 }
                }
        } else {
            GeometryReader { geo in
                ForEach(particles) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.width, height: p.height)
                        .rotationEffect(.degrees(drop ? p.endAngle : p.startAngle))
                        .position(
                            x: geo.size.width * p.x + (drop ? p.drift : 0),
                            y: drop ? geo.size.height + 30 : -10
                        )
                        .opacity(drop ? 0 : 1)
                        .animation(.easeIn(duration: p.duration).delay(p.delay), value: drop)
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .onAppear { drop = true }
        }
    }
}
