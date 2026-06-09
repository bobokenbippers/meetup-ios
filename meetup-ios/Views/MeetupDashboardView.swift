import SwiftUI
import MapKit
import PhotosUI
import Combine
import Supabase

struct MeetupDashboardView: View {
    @State private var meetup: Meetup
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth

    @Environment(AppSettings.self) private var settings

    init(meetup: Meetup) {
        _meetup = State(initialValue: meetup)
    }

    @State private var participants: [MeetupParticipant] = []
    @State private var showEditLocation = false
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?
    @State private var showCancelConfirm = false
    @State private var showBill = false
    @State private var showConfetti = false
    @State private var shareURL: URL?
    @State private var isGeneratingShareLink = false
    @State private var showRecap = false
    @State private var showAddParticipants = false

    // Photo state
    @State private var recentPhotos: [MeetupPhoto] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var isUploadingPhotos = false
    @State private var fullscreenPhoto: MeetupPhoto?

    private var myUserId: UUID? { auth.session?.user.id }
    private var myStatus: String? { participants.first(where: { $0.userId == myUserId })?.status }
    private var destinationCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
    }
    private var acceptedCount: Int {
        participants.filter { $0.isEnRoute || $0.status == "maybe" || $0.status == "arrived" }.count
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
                    if meetup.status == "active" && !meetup.isRecap {
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

                // Photo thumbnail strip (shown when photos exist)
                if !recentPhotos.isEmpty {
                    photoStrip
                        .padding(.bottom, 0)
                }

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
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 4) {
                        // Photo upload button
                        Button {
                            showPhotoPicker = true
                        } label: {
                            if isUploadingPhotos {
                                ProgressView().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "camera")
                            }
                        }
                        .disabled(isUploadingPhotos)

                        Button {
                            Task { await generateAndShare() }
                        } label: {
                            if isGeneratingShareLink {
                                ProgressView().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(isGeneratingShareLink)
                    }
                }
                if myUserId == meetup.hostId {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Cancel", role: .destructive) { showCancelConfirm = true }
                    }
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 4,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await uploadPickedPhotos(items) }
            }
            .sheet(isPresented: $showBill) {
                BillView(meetup: meetup, participants: participants)
                    .environment(auth)
                    .environment(settings)
            }
            .sheet(isPresented: $showRecap, onDismiss: { dismiss() }) {
                RecapView(meetup: meetup).environment(auth)
            }
            .sheet(isPresented: $showAddParticipants) {
                AddParticipantsSheet(
                    meetupId: meetup.id,
                    existingParticipantIds: Set(participants.map(\.userId)),
                    onAdded: { Task { await load() } }
                )
            }
            .sheet(isPresented: $showEditLocation) {
                EditMeetupLocationView(meetup: meetup) { updated in
                    meetup = updated
                    LocationManager.shared.updateTrackedDestination(meetup: updated)
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(url: url)
                    .ignoresSafeArea()
            }
            .sheet(item: $fullscreenPhoto) { photo in
                DashboardFullscreenPhotoView(photo: photo)
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
                await loadPhotos()
                await startRealtime()
                await startPhotoRealtime()
            }
            .onAppear {
                if meetup.isRecap { showRecap = true }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                if meetup.isRecap && !showRecap { showRecap = true }
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
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Sub-views

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(greeting), \(auth.profile?.displayName ?? "there") 👋")
                .scaledFont(size: 12)
                .foregroundStyle(Color(white: 0.55))
            Text(meetup.destinationName)
                .scaledFont(size: 24, weight: .black)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("You're meeting \(acceptedCount) \(acceptedCount == 1 ? "person" : "people")")
                .scaledFont(size: 12)
                .foregroundStyle(Color(white: 0.55))
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
                        .scaledFont(size: 18)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(meetup.destinationName)
                    .scaledFont(size: 13, weight: .bold)
                    .lineLimit(1)
                if let addr = meetup.destinationAddress {
                    Text(addr)
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let target = meetup.targetArrivalAt {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(target, format: .dateTime.hour().minute())
                        .scaledFont(size: 13, weight: .bold)
                    let mins = Int(target.timeIntervalSinceNow / 60)
                    if mins > 0 {
                        Text("in \(mins) min")
                            .scaledFont(size: 10, weight: .semibold)
                            .foregroundStyle(Color.coral)
                    }
                }
            }

            if myUserId == meetup.hostId && !meetup.isRecap {
                Button {
                    showEditLocation = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .scaledFont(size: 22)
                        .foregroundStyle(Color.coral)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit location")
                .accessibilityIdentifier("btn_edit_location")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.coral.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.coral.opacity(0.08), radius: 8, y: 2)
    }

    // MARK: - Photo strip

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentPhotos.prefix(6)) { photo in
                    AsyncImage(url: URL(string: photo.photoUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.appSurface
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                )
                        default:
                            Color.appSurface
                                .overlay(ProgressView().scaleEffect(0.7))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture { fullscreenPhoto = photo }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appSurface)
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.30))
                .frame(width: 32, height: 3)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // "Everyone" label + host "Add People" button
            HStack {
                Text("Everyone")
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(.white)
                if myUserId == meetup.hostId {
                    Spacer()
                    Button {
                        showAddParticipants = true
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.coral)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // Punctuality color legend
            PunctualityLegend(showsRunningLate: meetup.targetArrivalAt != nil)
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

            // RSVP buttons for invited participants
            if myStatus == "invited" {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("No") { Task { await respond(status: "no") } }
                            .buttonStyle(.glass)
                            .disabled(isActing)
                        Button("Maybe") { Task { await respond(status: "maybe") } }
                            .buttonStyle(.glass)
                            .disabled(isActing)
                        Button("Yes") { Task { await respond(status: "yes") } }
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
        .background(Color.appSurface)
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, topTrailing: 22)))
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, topTrailing: 22))
                .strokeBorder(Color.coral.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: Color.coral.opacity(0.08), radius: 16, y: -4)
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

    private func loadPhotos() async {
        do {
            let photos = try await MeetupPhotoService.shared.fetchPhotos(meetupId: meetup.id)
            recentPhotos = photos
        } catch is CancellationError {
            return
        } catch {
            // Non-fatal: photos are supplemental
        }
    }

    private func startPhotoRealtime() async {
        let channel = SupabaseManager.shared.client.realtimeV2.channel("meetup-photos-\(meetup.id)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "meetup_photos")
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await loadPhotos()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }

    private func uploadPickedPhotos(_ items: [PhotosPickerItem]) async {
        isUploadingPhotos = true
        defer {
            isUploadingPhotos = false
            selectedPhotoItems = []
        }
        for item in items {
            guard !Task.isCancelled else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { continue }
                let urlString = try await MeetupPhotoService.shared.uploadPhoto(image: uiImage, meetupId: meetup.id)
                try await MeetupPhotoService.shared.insertPhoto(meetupId: meetup.id, url: urlString, caption: nil)
            } catch is CancellationError {
                break
            } catch {
                self.error = error.localizedDescription
            }
        }
        await loadPhotos()
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
            if myParticipant?.status == "yes" && meetup.status == "active" {
                LocationManager.shared.requestPermission()
                LocationManager.shared.startTracking(meetup: meetup)
            }
            // Stop tracking when the view is open and the event window has expired.
            if let target = meetup.targetArrivalAt,
               Date() > target.addingTimeInterval(5400),
               LocationManager.shared.isTracking {
                LocationManager.shared.stopTracking()
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    private var myParticipant: MeetupParticipant? {
        participants.first(where: { $0.userId == myUserId })
    }

    private func generateAndShare() async {
        isGeneratingShareLink = true
        do {
            let token = try await MeetupService.shared.ensureShareToken(for: meetup)
            // Deep link into the app via the registered custom URL scheme (see Info.plist
            // CFBundleURLTypes). Must NOT be a raw Supabase API/Edge-Function URL — opening
            // that in a browser sends no auth header and Supabase returns
            // UNAUTHORIZED_NO_AUTH_HEADER. The app's onOpenURL handler routes this to JoinMeetupSheet.
            let urlString = "squadbrunch://join/\(token)"
            if let url = URL(string: urlString) {
                shareURL = url
            }
        } catch is CancellationError {
            // nothing
        } catch {
            self.error = error.localizedDescription
        }
        isGeneratingShareLink = false
    }

    private func respond(status: String) async {
        isActing = true
        do {
            switch status {
            case "yes":
                try await MeetupService.shared.accept(meetupId: meetup.id)
                withAnimation { showConfetti = true }
                Task {
                    do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
                    showConfetti = false
                }
            case "maybe":
                try await MeetupService.shared.maybe(meetupId: meetup.id)
            default:
                try await MeetupService.shared.decline(meetupId: meetup.id)
            }
            await load()
        } catch {
            self.error = error.localizedDescription
        }
        isActing = false
    }
}

// MARK: - URL Identifiable (for sheet(item:))

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
        if participant.status == "no" || participant.status == "declined" { return "Not coming" }
        if participant.status == "maybe" { return "Maybe" }
        if let late = participant.lateLabel(target: targetArrivalAt) { return late }
        return participant.etaLabel() ?? "On the way"
    }

    private var etaColor: Color {
        if participant.status == "arrived" { return .secondary }
        if participant.status == "no" || participant.status == "declined" { return .statusLate.opacity(0.7) }
        if participant.status == "maybe" { return .statusPending }
        if participant.lateLabel(target: targetArrivalAt) != nil { return .statusLate }
        return .statusLive
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
                            .scaledFont(size: 13, weight: .bold)
                            .foregroundStyle(.white)
                    }
                    .shadow(radius: 3)

                // Callout bubble
                VStack(alignment: .leading, spacing: 1) {
                    Text(participant.displayName ?? "?")
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(.white)
                    Text(etaText)
                        .scaledFont(size: 9, weight: .semibold)
                        .foregroundStyle(etaColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(white: 0.20), lineWidth: 1)
                )
            }
        }
    }
}

private enum ParticipantPalette {
    static func color(for userId: UUID) -> Color {
        Color.participantPalette[abs(userId.hashValue) % Color.participantPalette.count]
    }
}

private func pinColor(for userId: UUID) -> Color { ParticipantPalette.color(for: userId) }

// MARK: - Participant Row (in bottom panel)

private struct DashboardParticipantRow: View {
    let participant: MeetupParticipant
    let isMe: Bool
    let targetArrivalAt: Date?

    private var etaText: String {
        if participant.status == "arrived"  { return "✓ Here" }
        if participant.status == "no" || participant.status == "declined" { return "Not coming" }
        if participant.status == "maybe"    { return "Maybe coming" }
        if participant.status == "invited"  { return "Invited" }
        if let late = participant.lateLabel(target: targetArrivalAt) { return late }
        return participant.etaLabel() ?? "On the way"
    }

    private var etaColor: Color {
        if participant.status == "arrived" { return .secondary }
        if participant.status == "no" || participant.status == "declined" { return .statusLate.opacity(0.7) }
        if participant.status == "maybe"   { return .statusPending }
        if participant.status == "invited" { return .statusPending }
        if participant.lateLabel(target: targetArrivalAt) != nil { return .statusLate }
        return .statusLive
    }

    private var punctualityTint: Color? {
        guard let target = targetArrivalAt,
              participant.status != "arrived"
        else { return nil }
        switch participant.punctualityState(target: target) {
        case .early:        return Color.statusLive.opacity(0.12)
        case .onTime:       return nil
        case .cuttingClose: return Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.18)
        case .late:         return Color.orange.opacity(0.18)
        case .veryLate:     return Color.statusLate.opacity(0.15)
        case .none:         return nil
        }
    }

    private var punctualityAccent: Color? {
        guard let target = targetArrivalAt,
              participant.status != "arrived"
        else { return nil }
        switch participant.punctualityState(target: target) {
        case .early:        return Color.statusLive
        case .onTime:       return nil
        case .cuttingClose: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case .late:         return Color.orange
        case .veryLate:     return Color.statusLate
        case .none:         return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(pinColor(for: participant.userId).opacity(0.8))
                .frame(width: 30, height: 30)
                .overlay {
                    if participant.status == "arrived" {
                        Image(systemName: "checkmark")
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(.white)
                    } else {
                        Text(String((participant.displayName ?? "?").prefix(1)).uppercased())
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(.white)
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(participant.displayName ?? "Unknown")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(.white)
                    if isMe {
                        Text("(you)")
                            .scaledFont(size: 11)
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
                Text(etaText)
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(etaColor)
            }

            Spacer()

            PunctualityTile(
                rawStatus: participant.status,
                targetArrivalAt: targetArrivalAt
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(punctualityTint)
        .overlay(alignment: .leading) {
            if let accent = punctualityAccent {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: participant.etaSeconds)
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
        let palette: [Color] = [.pink, .purple, .blue, .coral, .statusPending, .green, .red, .cyan, .mint, .indigo]
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

// MARK: - Dashboard Fullscreen Photo

private struct DashboardFullscreenPhotoView: View {
    let photo: MeetupPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                AsyncImage(url: URL(string: photo.photoUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        Image(systemName: "photo")
                            .scaledFont(size: 48)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption)
                        .scaledFont(size: 14)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 28)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(20)
            }
        }
    }
}
