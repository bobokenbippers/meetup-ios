import Foundation
import Testing
@testable import meetup_ios

@Suite("Punctuality status")
struct PunctualityStatusTests {
    private let now = Date(timeIntervalSince1970: 1_800)

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
}
