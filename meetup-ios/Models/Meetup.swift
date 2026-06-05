import Foundation

struct Meetup: Codable, Identifiable, Equatable {
    let id: UUID
    let hostId: UUID
    let destinationName: String
    let destinationAddress: String?
    let destinationLat: Double
    let destinationLng: Double
    let targetArrivalAt: Date?
    let startsAt: Date
    let endsAt: Date
    let status: String
    let shareToken: String?
    let createdAt: Date
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id, status, category
        case hostId = "host_id"
        case destinationName = "destination_name"
        case destinationAddress = "destination_address"
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
        case targetArrivalAt = "target_arrival_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case shareToken = "share_token"
        case createdAt = "created_at"
    }

    var isRecap: Bool {
        if status != "active" { return true }
        let window: TimeInterval = 1.5 * 3600
        if let target = targetArrivalAt {
            return Date() > target.addingTimeInterval(window)
        }
        return Date() > createdAt.addingTimeInterval(6 * 3600)
    }
}

struct MeetupParticipant: Codable, Identifiable, Equatable {
    let meetupId: UUID
    let userId: UUID
    let status: String
    let lat: Double?
    let lng: Double?
    let bearing: Double?
    let etaSeconds: Int?
    let locationUpdatedAt: Date?
    let profiles: ParticipantProfile?

    struct ParticipantProfile: Codable, Equatable {
        let displayName: String?
        let phoneE164: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case phoneE164 = "phone_e164"
        }
    }

    var id: UUID { userId }
    var displayName: String? { profiles?.displayName }

    enum CodingKeys: String, CodingKey {
        case meetupId = "meetup_id"
        case userId = "user_id"
        case status
        case lat, lng, bearing
        case etaSeconds = "eta_seconds"
        case locationUpdatedAt = "location_updated_at"
        case profiles
    }
}

enum PunctualityState {
    case early, onTime, cuttingClose, late, veryLate
}

extension MeetupParticipant {
    var isEnRoute: Bool { status == "yes" || status == "accepted" }

    func punctualityState(target: Date) -> PunctualityState? {
        guard isEnRoute, let seconds = etaSeconds else { return nil }
        let delta = Date().addingTimeInterval(TimeInterval(seconds)).timeIntervalSince(target)
        switch delta {
        case ..<(-300):  return .early
        case -300..<300: return .onTime
        case 300..<900:  return .cuttingClose
        case 900..<1800: return .late
        default:         return .veryLate
        }
    }

    func etaLabel() -> String? {
        guard let seconds = etaSeconds, isEnRoute else { return nil }
        let minutes = seconds / 60
        if minutes < 1 { return "Almost there" }
        if minutes < 60 { return "\(minutes) min away" }
        return "\(minutes / 60)h \(minutes % 60)m away"
    }

    func lateLabel(target: Date?) -> String? {
        guard let target, let seconds = etaSeconds, isEnRoute else { return nil }
        let arrivalETA = Date().addingTimeInterval(TimeInterval(seconds))
        guard arrivalETA > target else { return nil }
        let lateBy = Int(arrivalETA.timeIntervalSince(target)) / 60
        return "\(lateBy) min late"
    }
}

struct MyParticipation: Codable, Identifiable, Equatable {
    let status: String
    let meetup: Meetup

    var id: UUID { meetup.id }

    enum CodingKeys: String, CodingKey {
        case status
        case meetup = "meetups"
    }
}
