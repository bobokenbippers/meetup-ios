import SwiftUI

// MARK: - Punctuality Status

/// At-a-glance, color-coded punctuality + attendance status for a meetup participant.
///
/// The underlying `meetup_participants.status` column is free text. In this codebase the
/// RSVP flow writes `"yes"` / `"no"` / `"maybe"` / `"invited"` / `"arrived"`, while some
/// older paths and the spec use `"accepted"` / `"declined"`. Both spellings are handled.
///
/// The `.runningLate` state is *derived*, not stored: if the meetup has a target arrival
/// time and a participant who has committed (accepted) or not yet responded (invited) has
/// blown past that time without arriving, they get the amber "running late" treatment,
/// which overrides the normal blue/gray.
enum PunctualityStatus {
    case arrived       // green
    case enRoute       // blue   — accepted / on the way, not yet arrived
    case invited       // gray   — no response yet
    case declined      // red
    case maybe         // lavender — tentative
    case runningLate   // amber  — committed/invited but past start time without arriving

    /// Resolve a participant's status string + the meetup's optional start time into a
    /// single display state, applying the "running late" override where appropriate.
    ///
    /// - Parameters:
    ///   - status: the raw `meetup_participants.status` value.
    ///   - targetArrivalAt: the meetup's start/target arrival time (`Meetup.targetArrivalAt`).
    ///   - now: injectable clock for testing; defaults to `Date()`.
    static func resolve(status: String, targetArrivalAt: Date?, now: Date = Date()) -> PunctualityStatus {
        switch status {
        case "arrived":
            return .arrived
        case "no", "declined":
            return .declined
        case "maybe":
            // Tentative attendees can still be flagged late if they blow past the start time.
            if isPastStart(targetArrivalAt, now: now) { return .runningLate }
            return .maybe
        case "yes", "accepted":
            if isPastStart(targetArrivalAt, now: now) { return .runningLate }
            return .enRoute
        case "invited":
            if isPastStart(targetArrivalAt, now: now) { return .runningLate }
            return .invited
        default:
            return .invited
        }
    }

    /// True when the meetup has a start time and `now` is past it (so a not-yet-arrived
    /// participant counts as running late).
    private static func isPastStart(_ targetArrivalAt: Date?, now: Date) -> Bool {
        guard let target = targetArrivalAt else { return false }
        return now > target
    }

    var color: Color {
        switch self {
        case .arrived:     return .statusLive
        case .enRoute:     return .statusEnRoute
        case .invited:     return .statusInvited
        case .declined:    return .statusLate
        case .maybe:       return .statusPending
        case .runningLate: return .statusRunningLate
        }
    }

    var label: String {
        switch self {
        case .arrived:     return "Arrived"
        case .enRoute:     return "On the way"
        case .invited:     return "Invited"
        case .declined:    return "Declined"
        case .maybe:       return "Maybe"
        case .runningLate: return "Running late"
        }
    }

    /// SF Symbol shown inside the tile.
    var systemImage: String {
        switch self {
        case .arrived:     return "checkmark.circle.fill"
        case .enRoute:     return "location.fill"
        case .invited:     return "envelope.fill"
        case .declined:    return "xmark.circle.fill"
        case .maybe:       return "questionmark.circle.fill"
        case .runningLate: return "clock.badge.exclamationmark.fill"
        }
    }
}

// MARK: - Punctuality Tile

/// Small, reusable color-coded status tile for a single participant row.
struct PunctualityTile: View {
    let status: PunctualityStatus
    /// When `true`, only the colored square + icon is shown (compact). When `false`,
    /// the label text is shown alongside it.
    var compact: Bool = false

    init(status: PunctualityStatus, compact: Bool = false) {
        self.status = status
        self.compact = compact
    }

    /// Convenience: resolve directly from a raw status string + the meetup start time.
    init(rawStatus: String, targetArrivalAt: Date?, compact: Bool = false) {
        self.status = PunctualityStatus.resolve(status: rawStatus, targetArrivalAt: targetArrivalAt)
        self.compact = compact
    }

    var body: some View {
        if compact {
            tile
        } else {
            HStack(spacing: 6) {
                tile
                Text(status.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(status.color)
            }
        }
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(status.color.opacity(0.18))
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(status.color.opacity(0.45), lineWidth: 1)
            )
            .overlay(
                Image(systemName: status.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(status.color)
            )
            .accessibilityLabel(status.label)
    }
}

// MARK: - Legend

/// Compact, wrapping legend explaining the punctuality tile colors. Only the states that
/// are actually reachable for the current meetup are shown (the "Running late" entry is
/// hidden when the meetup has no start time, since it can never occur).
struct PunctualityLegend: View {
    let showsRunningLate: Bool

    private var entries: [PunctualityStatus] {
        var all: [PunctualityStatus] = [.arrived, .enRoute, .invited, .declined]
        if showsRunningLate { all.insert(.runningLate, at: 2) }
        return all
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, status in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(status.color)
                            .frame(width: 9, height: 9)
                        Text(status.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.6))
                    }
                }
            }
        }
    }
}
