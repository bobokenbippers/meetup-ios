import SwiftUI

func participantPresenceStyle(
    for participant: MeetupParticipant,
    isMe: Bool,
    targetArrivalAt: Date?
) -> AvatarPresenceStyle {
    let punctuality = PunctualityStatus.resolve(
        status: participant.status,
        hasLiveETA: participant.hasLiveETA,
        targetArrivalAt: targetArrivalAt
    )

    switch punctuality {
    case .arrived:
        return AvatarPresenceStyle(
            ringColor: .statusLive,
            ringWidth: isMe ? 3 : 2.5,
            glowColor: .statusLive,
            glowRadius: 8,
            badge: .arrived,
            overlayLabel: nil
        )
    case .enRoute:
        return AvatarPresenceStyle(
            ringColor: isMe ? .coral : .statusEnRoute,
            ringWidth: isMe ? 3 : 2.5,
            glowColor: .statusEnRoute,
            glowRadius: 10,
            badge: .live
        )
    case .runningLate:
        return AvatarPresenceStyle(
            ringColor: .statusRunningLate,
            ringWidth: isMe ? 3 : 2.5,
            glowColor: .statusRunningLate,
            glowRadius: 9,
            badge: .late
        )
    case .invited:
        return AvatarPresenceStyle(
            ringColor: Color.statusInvited.opacity(0.45),
            ringWidth: 1.5,
            badge: .invited
        )
    case .going:
        return AvatarPresenceStyle(
            ringColor: .statusGoing,
            ringWidth: isMe ? 3 : 2
        )
    case .declined, .maybe:
        return AvatarPresenceStyle()
    }
}

struct SquadAvatarStrip: View {
    let participants: [MeetupParticipant]
    let currentUserId: UUID?
    let targetArrivalAt: Date?

    private var visibleParticipants: [MeetupParticipant] {
        Array(participants.prefix(4))
    }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(visibleParticipants) { participant in
                ProfileAvatarView(
                    displayName: participant.displayName,
                    avatarUrl: participant.avatarUrl,
                    userId: participant.userId,
                    size: 28,
                    fontSize: 11,
                    presenceStyle: participantPresenceStyle(
                        for: participant,
                        isMe: participant.userId == currentUserId,
                        targetArrivalAt: targetArrivalAt
                    )
                )
                .background(
                    Circle()
                        .fill(Color.appSurface)
                )
            }

            if participants.count > visibleParticipants.count {
                Text("+\(participants.count - visibleParticipants.count)")
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.appBackground)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.coral.opacity(0.18), lineWidth: 1))
                    .padding(.leading, 10)
            }
        }
    }
}

struct DashboardParticipantPin: View {
    let participant: MeetupParticipant
    let isMe: Bool
    let targetArrivalAt: Date?

    private var punctualityStatus: PunctualityStatus {
        PunctualityStatus.resolve(
            status: participant.status,
            hasLiveETA: participant.hasLiveETA,
            targetArrivalAt: targetArrivalAt
        )
    }

    private var etaText: String {
        if let late = participant.lateLabel(target: targetArrivalAt) { return late }
        return participant.etaLabel() ?? punctualityStatus.label
    }

    private var etaColor: Color {
        if participant.lateLabel(target: targetArrivalAt) != nil { return .statusLate }
        return punctualityStatus.color
    }

    var body: some View {
        HStack(spacing: 6) {
            ProfileAvatarView(
                displayName: participant.displayName,
                avatarUrl: participant.avatarUrl,
                userId: participant.userId,
                size: isMe ? 38 : 34,
                fontSize: 13,
                presenceStyle: participantPresenceStyle(
                    for: participant,
                    isMe: isMe,
                    targetArrivalAt: targetArrivalAt
                )
            )
            .overlay(Circle().strokeBorder(.white, lineWidth: isMe ? 3 : 2.5))
            .shadow(radius: 4)
            .accessibilityHidden(true)

            if !isMe || participant.hasLiveETA || participant.status == "arrived" {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMe ? "You" : (participant.displayName ?? "?"))
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(etaText)
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(etaColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.appSurface.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder((isMe ? Color.coral : etaColor).opacity(0.22), lineWidth: 1)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isMe ? "You" : (participant.displayName ?? "Participant")), \(etaText)")
            }
        }
    }
}

struct DashboardParticipantRow: View {
    let participant: MeetupParticipant
    let isMe: Bool
    let targetArrivalAt: Date?
    let canNudge: Bool
    let isNudging: Bool
    let onNudge: () -> Void

    private var punctualityStatus: PunctualityStatus {
        PunctualityStatus.resolve(
            status: participant.status,
            hasLiveETA: participant.hasLiveETA,
            targetArrivalAt: targetArrivalAt
        )
    }

    private var etaText: String {
        if let late = participant.lateLabel(target: targetArrivalAt) { return late }
        return participant.etaLabel() ?? punctualityStatus.label
    }

    private var etaColor: Color {
        if participant.lateLabel(target: targetArrivalAt) != nil { return .statusLate }
        return punctualityStatus.color
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

    private var isRunningLate: Bool {
        punctualityStatus == .runningLate
    }

    private var accessibilitySummary: String {
        let name = participant.displayName ?? "Unknown"
        let youSuffix = isMe ? ", you" : ""
        let lateTax = isRunningLate ? ", late tax in play" : ""
        return "\(name)\(youSuffix), \(etaText)\(lateTax)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                displayName: participant.displayName,
                avatarUrl: participant.avatarUrl,
                userId: participant.userId,
                size: 30,
                fontSize: 12,
                presenceStyle: participantPresenceStyle(
                    for: participant,
                    isMe: isMe,
                    targetArrivalAt: targetArrivalAt
                )
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(participant.displayName ?? "Unknown")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(DS.Color.textPrimary)
                    if isMe {
                        Text("(you)")
                            .scaledFont(size: 11)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
                Text(etaText)
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(etaColor)
                if isRunningLate {
                    Label("Late tax", systemImage: "bolt.fill")
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(Color.statusRunningLate)
                        .labelStyle(.titleAndIcon)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                PunctualityTile(
                    rawStatus: participant.status,
                    hasLiveETA: participant.hasLiveETA,
                    targetArrivalAt: targetArrivalAt
                )
                .accessibilityHidden(true)

                if canNudge {
                    Button(action: onNudge) {
                        HStack(spacing: 5) {
                            if isNudging {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "bell.badge")
                            }
                            Text(isNudging ? "Nudging..." : "Nudge")
                        }
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.coral.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.coral.opacity(0.22), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isNudging)
                    .accessibilityLabel("Nudge \(participant.displayName ?? "participant")")
                    .accessibilityHint("Sends a reminder to respond to this meetup.")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(punctualityTint)
        .overlay(alignment: .leading) {
            if let accent = punctualityAccent {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: canNudge ? .contain : .combine)
        .animation(.easeInOut(duration: 0.3), value: participant.etaSeconds)
    }
}
