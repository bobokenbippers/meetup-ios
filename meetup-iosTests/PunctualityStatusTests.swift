import Foundation
import Testing
@testable import meetup_ios

@Suite("Punctuality status")
struct PunctualityStatusTests {
    private let now = Date(timeIntervalSince1970: 1_800)

    private func makeParticipant(
        status: String = "accepted",
        etaSeconds: Int? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) -> MeetupParticipant {
        MeetupParticipant(
            meetupId: UUID(),
            userId: UUID(),
            status: status,
            lat: lat,
            lng: lng,
            bearing: nil,
            etaSeconds: etaSeconds,
            locationUpdatedAt: nil,
            profiles: .init(displayName: "Jayko", phoneE164: nil)
        )
    }

    @Test("accepted RSVP without live ETA resolves to going")
    func acceptedWithoutLiveETAIsGoing() {
        let target = now.addingTimeInterval(300)

        #expect(PunctualityStatus.resolve(
            status: "yes",
            hasLiveETA: false,
            targetArrivalAt: target,
            now: now
        ) == .going)
    }

    @Test("accepted RSVP with live ETA resolves to en route")
    func acceptedWithLiveETAIsEnRoute() {
        let target = now.addingTimeInterval(300)

        #expect(PunctualityStatus.resolve(
            status: "accepted",
            hasLiveETA: true,
            targetArrivalAt: target,
            now: now
        ) == .enRoute)
    }

    @Test("accepted RSVP past start resolves to running late")
    func acceptedPastStartIsRunningLate() {
        let target = now.addingTimeInterval(-60)

        #expect(PunctualityStatus.resolve(
            status: "yes",
            hasLiveETA: false,
            targetArrivalAt: target,
            now: now
        ) == .runningLate)
    }

    @Test("invited participant past start stays invited")
    func invitedPastStartIsNotRunningLate() {
        let target = now.addingTimeInterval(-60)

        #expect(PunctualityStatus.resolve(
            status: "invited",
            hasLiveETA: false,
            targetArrivalAt: target,
            now: now
        ) == .invited)
    }

    @Test("maybe participant past start stays maybe")
    func maybePastStartIsNotRunningLate() {
        let target = now.addingTimeInterval(-60)

        #expect(PunctualityStatus.resolve(
            status: "maybe",
            hasLiveETA: false,
            targetArrivalAt: target,
            now: now
        ) == .maybe)
    }

    @Test("late tax filter excludes invited and declined participants")
    func lateTaxFilterOnlyIncludesCommittedLateParticipants() {
        let target = now.addingTimeInterval(-60)
        let statuses = ["invited", "declined", "no", "maybe", "yes", "accepted"]

        let lateStatuses = statuses.filter {
            PunctualityStatus.resolve(
                status: $0,
                hasLiveETA: false,
                targetArrivalAt: target,
                now: now
            ) == .runningLate
        }

        #expect(lateStatuses == ["yes", "accepted"])
    }

    @Test("late ETA label shows route time without adding elapsed start time")
    func lateETALabelKeepsTransitTimeVisible() {
        let participant = makeParticipant(
            etaSeconds: 1_800,
            lat: 40.7128,
            lng: -74.0060
        )
        let target = now.addingTimeInterval(-1_800)

        #expect(participant.lateLabel(target: target, now: now) == "30 min away")
    }

    @Test("late ETA label does not turn one minute away into sixty-one minutes late")
    func lateETALabelKeepsTransitTimeVisibleBeyondAnHour() {
        let participant = makeParticipant(
            etaSeconds: 60,
            lat: 40.7128,
            lng: -74.0060
        )
        let target = now.addingTimeInterval(-3_600)

        #expect(participant.lateLabel(target: target, now: now) == "1 min away")
    }

    @Test("late ETA label is hidden when arrival is on time")
    func lateETALabelHiddenWhenArrivalIsOnTime() {
        let participant = makeParticipant(
            etaSeconds: 1_800,
            lat: 40.7128,
            lng: -74.0060
        )
        let target = now.addingTimeInterval(1_800)

        #expect(participant.lateLabel(target: target, now: now) == nil)
    }

    @Test("recap attendance includes arrived and committed participants")
    func recapAttendanceIncludesArrivedAndCommittedParticipants() {
        let statuses = ["arrived", "yes", "accepted", "invited", "maybe", "declined", "no"]
        let counted = statuses.filter {
            makeParticipant(status: $0).countsAsRecapAttendance
        }

        #expect(counted == ["arrived", "yes", "accepted"])
    }
}
