import SwiftUI
import MapKit
import PhotosUI
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
    @State private var showEditMeetup = false
    @State private var hasLoaded = false
    @State private var isActing = false
    @State private var error: String?
    @State private var showCancelConfirm = false
    @State private var showBill = false
    @State private var showComments = false
    @State private var showConfetti = false
    @State private var shareInvite: ShareInvite?
    @State private var isGeneratingShareLink = false
    @State private var showRecap = false
    @State private var showAddParticipants = false
    @State private var showStopSharingConfirm = false
    @State private var isStartingSharing = false
    @State private var isStoppingSharing = false
    @State private var isDrawerExpanded = false
    @State private var nudgingParticipantIds: Set<UUID> = []

    // Photo state
    @State private var recentPhotos: [MeetupPhoto] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var isUploadingPhotos = false
    @State private var fullscreenPhoto: MeetupPhoto?
    @State private var now = Date()
    @State private var latePunishmentVotes: [LatePunishmentVote] = []
    @State private var latePunishmentProofs: [LatePunishmentProof] = []
    @State private var lateProofReactionSummaries: [UUID: [LatePunishmentProofReactionSummary]] = [:]
    @State private var selectedLateProofItem: PhotosPickerItem?
    @State private var isVotingLatePunishment = false
    @State private var isUploadingLateProof = false
    @State private var reactingLateProofId: UUID?

    private var myUserId: UUID? { auth.session?.user.id }
    private var myStatus: String? { participants.first(where: { $0.userId == myUserId })?.status }
    private var destinationCoord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
    }
    private var meetingCount: Int {
        participants.filter { participant in
            participant.userId != myUserId
                && participant.status != "no"
                && participant.status != "declined"
        }.count
    }
    private var lateParticipants: [MeetupParticipant] {
        guard meetup.status == "active", let target = meetup.targetArrivalAt else { return [] }
        return participants.filter { participant in
            PunctualityStatus.resolve(
                status: participant.status,
                hasLiveETA: participant.hasLiveETA,
                targetArrivalAt: target,
                now: now
            ) == .runningLate
        }
    }
    private var latePunishment: LatePunishment? {
        guard !lateParticipants.isEmpty else { return nil }
        return LatePunishment(
            lateParticipants: lateParticipants,
            votes: latePunishmentVotes,
            currentUserId: myUserId
        )
    }
    private var canShareLocation: Bool {
        myStatus == "yes" && meetup.status == "active" && UserSettingsService.locationSharingEnabled
    }
    private var isSharingThisMeetup: Bool {
        LocationManager.shared.isTracking && LocationManager.shared.trackingMeetup?.id == meetup.id
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

    private var activeParticipants: [MeetupParticipant] {
        participants.filter { $0.status != "no" && $0.status != "declined" }
    }

    private var compactParticipantSummary: String {
        let arrivedCount = activeParticipants.filter { $0.status == "arrived" }.count
        let liveCount = activeParticipants.filter(\.hasLiveETA).count
        if arrivedCount > 0 {
            return "\(arrivedCount) arrived" + (liveCount > 0 ? " • \(liveCount) sharing live ETA" : "")
        }
        if liveCount > 0 {
            return "\(liveCount) sharing live ETA"
        }
        return "\(activeParticipants.count) in the squad"
    }

    private var isHost: Bool {
        myUserId == meetup.hostId
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    MeetupDashboardHeaderSection(
                        greeting: greeting,
                        displayName: auth.profile?.displayName ?? "there",
                        destinationName: meetup.destinationName,
                        meetingCount: meetingCount
                    )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    MeetupDashboardDestinationCard(
                        meetup: meetup,
                        isHost: myUserId == meetup.hostId && !meetup.isRecap,
                        onEdit: { showEditMeetup = true }
                    )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)

                    MeetupDashboardMapSection(
                        destinationCoord: destinationCoord,
                        participants: participants,
                        myUserId: myUserId,
                        meetupStatus: meetup.status,
                        isRecap: meetup.isRecap,
                        targetArrivalAt: meetup.targetArrivalAt
                    )
                }

                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .background(Color.appBackground)
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
                if isHost {
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
            .onChange(of: selectedLateProofItem) { _, item in
                guard let item else { return }
                Task { await uploadLatePunishmentProof(item) }
            }
            .sheet(isPresented: $showBill) {
                BillView(meetup: meetup, participants: participants)
                    .environment(auth)
                    .environment(settings)
            }
            .sheet(isPresented: $showComments) {
                MeetupCommentsView(meetup: meetup)
                    .environment(auth)
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
            .sheet(isPresented: $showEditMeetup) {
                EditMeetupView(meetup: meetup) { updated in
                    meetup = updated
                    LocationManager.shared.updateTrackedDestination(meetup: updated)
                }
            }
            .sheet(item: $shareInvite) { invite in
                ShareSheet(invite: invite)
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $fullscreenPhoto) { photo in
                MeetupPhotoPagerView(
                    photos: recentPhotos,
                    initialPhoto: photo,
                    currentUserId: myUserId,
                    meetupHostId: meetup.hostId,
                    onPhotoDeleted: { deleted in
                        recentPhotos.removeAll { $0.id == deleted.id }
                    }
                )
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
            .confirmationDialog(
                "Stop sharing your location?",
                isPresented: $showStopSharingConfirm,
                titleVisibility: .visible
            ) {
                Button("Stop Sharing", role: .destructive) {
                    Task { await stopSharing() }
                }
                Button("Keep Sharing", role: .cancel) {}
            } message: {
                Text("Your pin will disappear from everyone's map. You can't restart sharing once stopped.")
            }
            .task {
                await load()
                await loadPhotos()
                await startRealtime()
                await startPhotoRealtime()
            }
            .task(id: meetup.id) {
                await startLatePunishmentRealtime()
            }
            .task(id: meetup.id) {
                await startLatePunishmentProofRealtime()
            }
            .task(id: meetup.id) {
                await startLatePunishmentProofReactionRealtime()
            }
            .onAppear {
                if meetup.isRecap { showRecap = true }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                now = Date()
                if meetup.isRecap && !showRecap { showRecap = true }
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

    private var bottomPanel: some View {
        MeetupDashboardDrawer(
            isExpanded: isDrawerExpanded,
            summary: compactParticipantSummary,
            participants: participants,
            myUserId: myUserId,
            targetArrivalAt: meetup.targetArrivalAt,
            onToggle: {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isDrawerExpanded.toggle()
                }
            }
        ) {
            if isDrawerExpanded {
                expandedDrawerContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: myStatus)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isDrawerExpanded)
    }

    @ViewBuilder
    private var expandedDrawerContent: some View {
        VStack(spacing: 0) {
            if !recentPhotos.isEmpty {
                MeetupDashboardPhotoStrip(
                    photos: recentPhotos,
                    onSelect: { fullscreenPhoto = $0 },
                    onShowOverflow: { overflowPhoto in
                        fullscreenPhoto = overflowPhoto
                    }
                )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            HStack {
                if isHost {
                    Button {
                        showAddParticipants = true
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.coral)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            PunctualityLegend(showsRunningLate: meetup.targetArrivalAt != nil)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if let latePunishment {
                let latestProofReactions = latePunishmentProofs.first
                    .map { lateProofReactionSummaries[$0.id] ?? [] } ?? []
                LatePunishmentCard(
                    punishment: latePunishment,
                    proofs: latePunishmentProofs,
                    proofReactionSummaries: latestProofReactions,
                    isVoting: isVotingLatePunishment,
                    isUploadingProof: isUploadingLateProof,
                    reactingProofId: reactingLateProofId,
                    proofSelection: $selectedLateProofItem,
                    onVote: { option in
                        Task { await voteLatePunishment(option) }
                    },
                    onToggleProofReaction: { proof, emoji in
                        Task { await toggleLateProofReaction(proof: proof, emoji: emoji) }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if hasLoaded {
                VStack(spacing: 0) {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { idx, p in
                        DashboardParticipantRow(
                            participant: p,
                            isMe: p.userId == myUserId,
                            targetArrivalAt: meetup.targetArrivalAt,
                            canNudge: isHost && p.status == "invited",
                            isNudging: nudgingParticipantIds.contains(p.userId),
                            onNudge: {
                                Task { await nudgeParticipant(p) }
                            }
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

            if myStatus == "invited" {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Yes") { Task { await respond(status: "yes") } }
                            .buttonStyle(.glassProminent)
                            .disabled(isActing)
                        Button("Maybe") { Task { await respond(status: "maybe") } }
                            .buttonStyle(.glass)
                            .disabled(isActing)
                        Button("No") { Task { await respond(status: "no") } }
                            .buttonStyle(.glass)
                            .disabled(isActing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            MeetupDashboardQuickActions(
                onDirections: openDirections,
                onComments: { showComments = true },
                onBill: { showBill = true }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            MeetupDashboardLocationSharingSection(
                canShareLocation: canShareLocation,
                isSharingThisMeetup: isSharingThisMeetup,
                isStartingSharing: isStartingSharing,
                isStoppingSharing: isStoppingSharing,
                onStartOrStop: {
                    if isSharingThisMeetup {
                        showStopSharingConfirm = true
                    } else {
                        startSharing()
                    }
                },
                onStopOnly: { showStopSharingConfirm = true }
            )
        }
    }

    // MARK: - Logic

    private func startSharing() {
        guard !isStartingSharing else { return }
        isStartingSharing = true
        LocationManager.shared.requestPermission()
        LocationManager.shared.startTracking(meetup: meetup)
        isStartingSharing = false
    }

    private func stopSharing() async {
        guard !isStoppingSharing else { return }
        isStoppingSharing = true
        defer { isStoppingSharing = false }
        // Stop uploads first so no new location reaches Supabase after the clear.
        LocationManager.shared.stopTracking()
        do {
            try await MeetupService.shared.clearMyLocation(meetup: meetup)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openDirections() {
        let lat = meetup.destinationLat
        let lng = meetup.destinationLng
        let mode = LocationManager.shared.googleMapsDirectionsMode
        let gmNative = URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=\(mode)")!
        if UIApplication.shared.canOpenURL(gmNative) {
            UIApplication.shared.open(gmNative)
        } else {
            let gmWeb = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)&travelmode=\(mode)")!
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
            if !UserSettingsService.locationSharingEnabled,
               LocationManager.shared.trackingMeetup?.id == meetup.id {
                // User turned off location sharing while this meetup is in view.
                LocationManager.shared.stopTracking()
            }
            // Stop tracking when the view is open and the event window has expired.
            if let target = meetup.targetArrivalAt,
               Date() > target.addingTimeInterval(5400),
               LocationManager.shared.isTracking {
                LocationManager.shared.stopTracking()
            }
            await loadLatePunishmentVotes()
            await loadLatePunishmentProofs()
            await loadLatePunishmentProofReactions()
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
            let appURLString = "squadbrunch://join/\(token)"
            // Share a normal web URL so beta testers can forward it anywhere. The Edge
            // Function page redirects installed users into squadbrunch://join/<token>
            // and gives people without the app a useful fallback instead of a dead link.
            let urlString = "https://boyrqhbdkqzffvfokpri.supabase.co/functions/v1/join-meetup/\(token)"
            if let url = URL(string: urlString) {
                shareInvite = ShareInvite(
                    url: url,
                    message: "Join my Squad Brunch meetup at \(meetup.destinationName): \(url.absoluteString)\n\nIf that does not open the app, use: \(appURLString)"
                )
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

    private func nudgeParticipant(_ participant: MeetupParticipant) async {
        guard isHost, participant.status == "invited" else { return }
        guard !nudgingParticipantIds.contains(participant.userId) else { return }

        nudgingParticipantIds.insert(participant.userId)
        defer { nudgingParticipantIds.remove(participant.userId) }

        do {
            try await MeetupService.shared.nudgeParticipant(meetupId: meetup.id, userId: participant.userId)
            await load()
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn't send a nudge right now. Please try again."
            await load()
        }
    }

    private func loadLatePunishmentVotes() async {
        do {
            latePunishmentVotes = try await LatePunishmentService.shared.fetchVotes(meetupId: meetup.id)
        } catch is CancellationError {
            return
        } catch {
            latePunishmentVotes = []
        }
    }

    private func loadLatePunishmentProofs() async {
        do {
            latePunishmentProofs = try await LatePunishmentService.shared.fetchProofs(meetupId: meetup.id)
        } catch is CancellationError {
            return
        } catch {
            latePunishmentProofs = []
            lateProofReactionSummaries = [:]
        }
    }

    private func loadLatePunishmentProofReactions() async {
        guard !latePunishmentProofs.isEmpty else {
            lateProofReactionSummaries = [:]
            return
        }
        do {
            lateProofReactionSummaries = try await LatePunishmentService.shared
                .listProofReactionSummaries(meetupId: meetup.id)
        } catch is CancellationError {
            return
        } catch {
            lateProofReactionSummaries = [:]
        }
    }

    private func voteLatePunishment(_ option: LatePunishmentOption) async {
        guard !isVotingLatePunishment else { return }
        isVotingLatePunishment = true
        defer { isVotingLatePunishment = false }
        do {
            try await LatePunishmentService.shared.vote(meetupId: meetup.id, optionKey: option.key)
            await loadLatePunishmentVotes()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func uploadLatePunishmentProof(_ item: PhotosPickerItem) async {
        guard !isUploadingLateProof else { return }
        isUploadingLateProof = true
        defer {
            isUploadingLateProof = false
            selectedLateProofItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                error = "Could not read that evidence photo."
                return
            }
            try await LatePunishmentService.shared.uploadProof(image: image, meetupId: meetup.id)
            await loadLatePunishmentProofs()
            await loadLatePunishmentProofReactions()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleLateProofReaction(proof: LatePunishmentProof, emoji: String) async {
        guard reactingLateProofId == nil else { return }
        reactingLateProofId = proof.id
        defer { reactingLateProofId = nil }
        do {
            try await LatePunishmentService.shared.toggleProofReaction(proofId: proof.id, emoji: emoji)
            await loadLatePunishmentProofReactions()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startLatePunishmentRealtime() async {
        let channel = SupabaseManager.shared.client.realtimeV2
            .channel("late-punishment-votes-\(meetup.id)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "meetup_late_punishment_votes"
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await loadLatePunishmentVotes()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }

    private func startLatePunishmentProofRealtime() async {
        let channel = SupabaseManager.shared.client.realtimeV2
            .channel("late-punishment-proofs-\(meetup.id)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "meetup_late_punishment_proofs"
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await loadLatePunishmentProofs()
            await loadLatePunishmentProofReactions()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }

    private func startLatePunishmentProofReactionRealtime() async {
        let channel = SupabaseManager.shared.client.realtimeV2
            .channel("late-punishment-proof-reactions-\(meetup.id)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "meetup_late_punishment_proof_reactions"
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await loadLatePunishmentProofReactions()
        }
        await SupabaseManager.shared.client.realtimeV2.removeChannel(channel)
    }
}

// MARK: - Share Invite Payload

private struct ShareInvite: Identifiable {
    let url: URL
    let message: String

    var id: String { url.absoluteString }
}

// MARK: - Late Punishment

private struct LatePunishmentOption: Identifiable, Equatable {
    let key: String
    let title: String
    let systemImage: String

    var id: String { key }

    static let all: [LatePunishmentOption] = [
        LatePunishmentOption(key: "appetizer", title: "Appetizer", systemImage: "fork.knife"),
        LatePunishmentOption(key: "dare", title: "First dare", systemImage: "flame.fill"),
        LatePunishmentOption(key: "group_photo", title: "Group photo", systemImage: "camera.fill"),
        LatePunishmentOption(key: "next_spot", title: "Next spot", systemImage: "map.fill"),
        LatePunishmentOption(key: "best_excuse", title: "Best excuse", systemImage: "text.bubble.fill")
    ]
}

private struct LatePunishment {
    let title: String
    let detail: String
    let options: [LatePunishmentOption]
    let voteCounts: [String: Int]
    let selectedOptionKey: String?
    let winningOptionKey: String?
    let canVote: Bool

    init(
        lateParticipants: [MeetupParticipant],
        votes: [LatePunishmentVote],
        currentUserId: UUID?
    ) {
        let names = lateParticipants
            .map { $0.displayName?.split(separator: " ").first.map(String.init) ?? "Someone" }
        let displayNames = names.prefix(2).joined(separator: " + ")

        if lateParticipants.count == 1 {
            title = "\(displayNames) triggered the late tax"
        } else if lateParticipants.count == 2 {
            title = "\(displayNames) triggered the late tax"
        } else {
            title = "\(lateParticipants.count) people triggered the late tax"
        }

        let allOptions = LatePunishmentOption.all
        let counts = Dictionary(grouping: votes, by: \.optionKey).mapValues(\.count)
        let selected = currentUserId.flatMap { userId in
            votes.first(where: { $0.voterId == userId })?.optionKey
        }
        let userCanVote = currentUserId.map { userId in
            !lateParticipants.contains(where: { $0.userId == userId })
        } ?? false

        let winner = votes.isEmpty ? nil : allOptions.max { lhs, rhs in
            let lhsCount = counts[lhs.key, default: 0]
            let rhsCount = counts[rhs.key, default: 0]
            if lhsCount == rhsCount {
                return lhs.title > rhs.title
            }
            return lhsCount < rhsCount
        }?.key

        options = allOptions
        voteCounts = counts
        selectedOptionKey = selected
        canVote = userCanVote
        winningOptionKey = winner

        if !userCanVote {
            detail = "Late folks sit this vote out."
        } else if selected != nil {
            detail = "Your vote is in. Change it until the group settles it."
        } else {
            detail = "Vote on the punishment. Late folks cannot vote."
        }
    }
}

private struct LatePunishmentCard: View {
    let punishment: LatePunishment
    let proofs: [LatePunishmentProof]
    let proofReactionSummaries: [LatePunishmentProofReactionSummary]
    let isVoting: Bool
    let isUploadingProof: Bool
    let reactingProofId: UUID?
    @Binding var proofSelection: PhotosPickerItem?
    let onVote: (LatePunishmentOption) -> Void
    let onToggleProofReaction: (LatePunishmentProof, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundStyle(Color.statusRunningLate)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(punishment.title)
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(punishment.detail)
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(punishment.options) { option in
                    LatePunishmentVoteButton(
                        option: option,
                        count: punishment.voteCounts[option.key, default: 0],
                        isSelected: punishment.selectedOptionKey == option.key,
                        isWinning: punishment.winningOptionKey == option.key,
                        isDisabled: !punishment.canVote || isVoting,
                        onTap: { onVote(option) }
                    )
                }
            }

            Divider()
                .overlay(Color.statusRunningLate.opacity(0.20))

            HStack(spacing: 10) {
                if let proof = proofs.first,
                   let url = URL(string: proof.photoUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.appSurface
                                .overlay(Image(systemName: "photo"))
                        default:
                            Color.appSurface
                                .overlay(ProgressView().scaleEffect(0.65))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Evidence posted")
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(proof.createdAt, format: .dateTime.hour().minute())
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Evidence required")
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text("Post proof when the punishment is complete.")
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                PhotosPicker(selection: $proofSelection, matching: .images) {
                    Label(isUploadingProof ? "Posting" : "Post", systemImage: "camera.fill")
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(Color.statusRunningLate)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.statusRunningLate.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .disabled(isUploadingProof)
            }

            if let proof = proofs.first {
                LatePunishmentProofReactionRow(
                    summaries: proofReactionSummaries,
                    isReacting: reactingProofId == proof.id,
                    onToggle: { emoji in onToggleProofReaction(proof, emoji) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.statusRunningLate.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.statusRunningLate.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct LatePunishmentProofReactionRow: View {
    private let supportedEmojis = ["❤️", "😂", "😮", "😢", "🔥", "👍"]

    let summaries: [LatePunishmentProofReactionSummary]
    let isReacting: Bool
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(supportedEmojis, id: \.self) { emoji in
                    let summary = summaries.first(where: { $0.emoji == emoji })
                    Button {
                        onToggle(emoji)
                    } label: {
                        HStack(spacing: 4) {
                            Text(emoji)
                                .scaledFont(size: 12, weight: .semibold)
                            if let count = summary?.reactionCount, count > 0 {
                                Text("\(count)")
                                    .scaledFont(size: 10, weight: .bold)
                            }
                        }
                        .foregroundStyle(summary?.reactedByMe == true ? .white : DS.Color.textPrimary)
                        .frame(minWidth: 34, minHeight: 28)
                        .padding(.horizontal, 5)
                        .background(backgroundColor(isSelected: summary?.reactedByMe == true))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(borderColor(isSelected: summary?.reactedByMe == true), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isReacting)
                    .accessibilityLabel(reactionAccessibilityLabel(emoji: emoji, count: summary?.reactionCount ?? 0))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func backgroundColor(isSelected: Bool) -> Color {
        isSelected ? Color.statusRunningLate : Color.appSurface.opacity(0.92)
    }

    private func borderColor(isSelected: Bool) -> Color {
        isSelected ? Color.statusRunningLate : Color.statusRunningLate.opacity(0.18)
    }

    private func reactionAccessibilityLabel(emoji: String, count: Int) -> String {
        count == 1 ? "1 \(emoji) reaction" : "\(count) \(emoji) reactions"
    }
}

private struct LatePunishmentVoteButton: View {
    let option: LatePunishmentOption
    let count: Int
    let isSelected: Bool
    let isWinning: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: option.systemImage)
                    .scaledFont(size: 10, weight: .bold)
                Text(option.title)
                    .scaledFont(size: 10, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text("\(count)")
                    .scaledFont(size: 10, weight: .bold)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isSelected ? 0.58 : 1)
    }

    private var foregroundColor: Color {
        isSelected || isWinning ? Color.statusRunningLate : DS.Color.textPrimary
    }

    private var backgroundColor: Color {
        if isSelected { return Color.statusRunningLate.opacity(0.20) }
        if isWinning { return Color.statusRunningLate.opacity(0.12) }
        return Color.appSurface
    }

    private var borderColor: Color {
        isSelected || isWinning ? Color.statusRunningLate.opacity(0.45) : Color.statusInvited.opacity(0.25)
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

private struct ShareSheet: UIViewControllerRepresentable {
    let invite: ShareInvite

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [invite.message, invite.url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Destination Marker

struct DestinationMarker: View {
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
