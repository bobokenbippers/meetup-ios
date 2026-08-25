import SwiftUI
import MapKit

struct MeetupDashboardHeaderSection: View {
    let greeting: String
    let displayName: String
    let destinationName: String
    let meetingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting), \(displayName) 👋")
                .scaledFont(size: 12)
                .foregroundStyle(DS.Color.textSecondary)
            Text(destinationName)
                .scaledFont(size: 24, weight: .black)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
            Text("You're meeting \(meetingCount) \(meetingCount == 1 ? "person" : "people")")
                .scaledFont(size: 12)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(destinationName). You're meeting \(meetingCount) \(meetingCount == 1 ? "person" : "people").")
    }
}

struct MeetupDashboardDestinationCard: View {
    let meetup: Meetup
    let isHost: Bool
    let onEdit: () -> Void

    private var minutesUntilArrival: Int? {
        guard let target = meetup.targetArrivalAt else { return nil }
        let minutes = Int(target.timeIntervalSinceNow / 60)
        return minutes > 0 ? minutes : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.coral)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .scaledFont(size: 18)
                        .foregroundStyle(Color.appAccentForeground)
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(meetup.destinationName)
                    .scaledFont(size: 13, weight: .bold)
                    .lineLimit(1)
                if let addr = meetup.destinationAddress {
                    Text(addr)
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let target = meetup.targetArrivalAt {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(target, format: .dateTime.hour().minute())
                        .scaledFont(size: 13, weight: .bold)
                    if let minutesUntilArrival {
                        Text("in \(minutesUntilArrival) min")
                            .scaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(Color.coral)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Target arrival")
                .accessibilityValue(target.formatted(date: .omitted, time: .shortened))
            }

            if isHost {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .scaledFont(size: 22)
                        .foregroundStyle(Color.coral)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit meetup")
                .accessibilityIdentifier("btn_edit_meetup")
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
        .accessibilityElement(children: .contain)
        .accessibilityHint(isHost ? "Double tap the edit button to change meetup details." : "Shows the meetup destination and target arrival.")
    }
}

struct MeetupDashboardMapSection: View {
    let destinationCoord: CLLocationCoordinate2D
    let participants: [MeetupParticipant]
    let myUserId: UUID?
    let meetupStatus: String
    let isRecap: Bool
    let targetArrivalAt: Date?

    var body: some View {
        ZStack(alignment: .bottom) {
            Map {
                Annotation("", coordinate: destinationCoord) {
                    DestinationMarker()
                }
                if meetupStatus == "active" && !isRecap {
                    ForEach(participants) { participant in
                        if let lat = participant.lat, let lng = participant.lng {
                            Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                DashboardParticipantPin(
                                    participant: participant,
                                    isMe: participant.userId == myUserId,
                                    targetArrivalAt: targetArrivalAt
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.coral.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meetup map")
        .accessibilityHint("Shows the destination and live participant positions for this meetup.")
    }
}

struct MeetupDashboardPhotoStrip: View {
    let photos: [MeetupPhoto]
    let onSelect: (MeetupPhoto) -> Void
    let onShowOverflow: (MeetupPhoto) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.prefix(6).enumerated()), id: \.element.id) { index, photo in
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
                    .onTapGesture { onSelect(photo) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Photo \(index + 1) of \(min(photos.count, 6))")
                    .accessibilityHint("Opens the meetup photo viewer.")
                }

                if photos.count > 6, let overflowPhoto = photos[safe: 6] {
                    Button {
                        onShowOverflow(overflowPhoto)
                    } label: {
                        Text("+\(photos.count - 6)")
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color(white: 0.20))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(photos.count - 6) more photos")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appSurface)
    }
}

struct MeetupDashboardDrawer<Content: View>: View {
    let isExpanded: Bool
    let summary: String
    let participants: [MeetupParticipant]
    let myUserId: UUID?
    let targetArrivalAt: Date?
    let onToggle: () -> Void
    let content: Content

    init(
        isExpanded: Bool,
        summary: String,
        participants: [MeetupParticipant],
        myUserId: UUID?,
        targetArrivalAt: Date?,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.summary = summary
        self.participants = participants
        self.myUserId = myUserId
        self.targetArrivalAt = targetArrivalAt
        self.onToggle = onToggle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.30))
                        .frame(width: 34, height: 4)
                        .padding(.top, 10)
                        .accessibilityHidden(true)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Everyone")
                                .scaledFont(size: 14, weight: .bold)
                                .foregroundStyle(DS.Color.textPrimary)
                            Text(summary)
                                .scaledFont(size: 12, weight: .medium)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        SquadAvatarStrip(
                            participants: participants,
                            currentUserId: myUserId,
                            targetArrivalAt: targetArrivalAt
                        )
                        .accessibilityHidden(true)

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(DS.Color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse participants" : "Expand participants")
            .accessibilityValue(summary)

            content
        }
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.coral.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: Color.coral.opacity(0.12), radius: 18, y: 8)
    }
}

struct MeetupDashboardQuickActions: View {
    let onDirections: () -> Void
    let onComments: () -> Void
    let onBill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            quickActionButton("Directions", systemImage: "map.fill", action: onDirections)
            quickActionButton("Comments", systemImage: "text.bubble.fill", action: onComments)
            quickActionButton("Split Bill", systemImage: "receipt", action: onBill)
        }
    }

    private func quickActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Opens \(title.lowercased()).")
    }
}

struct MeetupDashboardLocationSharingSection: View {
    let canShareLocation: Bool
    let isSharingThisMeetup: Bool
    let isStartingSharing: Bool
    let isStoppingSharing: Bool
    let onStartOrStop: () -> Void
    let onStopOnly: () -> Void

    private var buttonTitle: String {
        if isStartingSharing { return "Starting..." }
        if isStoppingSharing { return "Stopping..." }
        return isSharingThisMeetup ? "Stop Sharing Location" : "Start Sharing Location"
    }

    private var buttonColor: Color {
        isSharingThisMeetup ? .statusRunningLate : .coral
    }

    private var helperText: String {
        if isSharingThisMeetup {
            return "Sharing stays on even after you close this screen. It stops only when you turn it off here, disable location sharing in Settings, or the meetup expires."
        }
        return "Live ETA updates continue in the background for this active meetup until you stop sharing or the meetup expires. This may use battery."
    }

    var body: some View {
        Group {
            if canShareLocation {
                VStack(alignment: .leading, spacing: 8) {
                    sharingButton(
                        title: buttonTitle,
                        color: buttonColor,
                        showsProgress: isStartingSharing || isStoppingSharing,
                        systemImage: isSharingThisMeetup ? "location.slash.fill" : "location.fill",
                        action: onStartOrStop
                    )
                    .accessibilityLabel(isSharingThisMeetup ? "Stop sharing your location" : "Start sharing your location")
                    .accessibilityHint(isSharingThisMeetup ? "Sharing continues until you stop it or the meetup expires." : "Turns on live ETA sharing for this meetup in the background.")
                    .accessibilityIdentifier(isSharingThisMeetup ? "btn_stop_sharing" : "btn_start_sharing")

                    Text(helperText)
                        .scaledFont(size: 12)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else if isSharingThisMeetup {
                VStack(alignment: .leading, spacing: 8) {
                    sharingButton(
                        title: isStoppingSharing ? "Stopping…" : "Stop Sharing Location",
                        color: .statusRunningLate,
                        showsProgress: isStoppingSharing,
                        systemImage: "location.slash.fill",
                        action: onStopOnly
                    )
                    .accessibilityLabel("Stop sharing your location")
                    .accessibilityHint("Sharing remains active even though new sharing cannot be started from here.")
                    .accessibilityIdentifier("btn_stop_sharing")

                    Text("Location sharing is still active for this meetup. Stop it here if you no longer want your live ETA shown.")
                        .scaledFont(size: 12)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Color.clear.frame(height: 8)
            }
        }
    }

    private func sharingButton(
        title: String,
        color: Color,
        showsProgress: Bool,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsProgress {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .scaledFont(size: 13, weight: .semibold)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isStartingSharing || isStoppingSharing)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
