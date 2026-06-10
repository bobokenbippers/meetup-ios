import Testing
import Foundation
@testable import meetup_ios

@Suite("Meetup list filtering")
struct MeetupFilteringTests {

    private func makeMeetup(
        status: String = "active",
        targetArrivalAt: Date? = nil,
        startsAt: Date = Date(),
        endsAt: Date = Date().addingTimeInterval(7200),
        createdAt: Date = Date()
    ) -> Meetup {
        Meetup(
            id: UUID(),
            hostId: UUID(),
            destinationName: "Test Place",
            destinationAddress: nil,
            destinationLat: 0,
            destinationLng: 0,
            targetArrivalAt: targetArrivalAt,
            startsAt: startsAt,
            endsAt: endsAt,
            status: status,
            shareToken: UUID().uuidString,
            createdAt: createdAt,
            category: nil
        )
    }

    private func makeParticipation(
        meetupStatus: String = "active",
        myStatus: String,
        targetArrivalAt: Date? = nil,
        startsAt: Date = Date(),
        endsAt: Date = Date().addingTimeInterval(7200),
        createdAt: Date = Date()
    ) -> MyParticipation {
        MyParticipation(
            status: myStatus,
            meetup: makeMeetup(
                status: meetupStatus,
                targetArrivalAt: targetArrivalAt,
                startsAt: startsAt,
                endsAt: endsAt,
                createdAt: createdAt
            )
        )
    }

    private func filter(_ participations: [MyParticipation]) -> (
        invited: [MyParticipation],
        active: [MyParticipation],
        past: [MyParticipation]
    ) {
        (
            MeetupListFilters.invited(participations),
            MeetupListFilters.active(participations),
            MeetupListFilters.past(participations)
        )
    }

    @Test("invited participation appears only in invited bucket")
    func invitedBucket() {
        let p = makeParticipation(myStatus: "invited")
        let result = filter([p])
        #expect(result.invited.count == 1)
        #expect(result.active.isEmpty)
        #expect(result.past.isEmpty)
    }

    @Test("accepted participation appears only in active bucket")
    func activeBucket() {
        let p = makeParticipation(myStatus: "accepted")
        let result = filter([p])
        #expect(result.invited.isEmpty)
        #expect(result.active.count == 1)
        #expect(result.past.isEmpty)
    }

    @Test("arrived participation appears in active bucket (meetup still active)")
    func arrivedInActiveBucket() {
        let p = makeParticipation(myStatus: "arrived")
        let result = filter([p])
        #expect(result.active.count == 1)
    }

    @Test("declined participation on active meetup appears in active bucket")
    func declinedOnActiveMeetup() {
        let p = makeParticipation(myStatus: "declined")
        let result = filter([p])
        #expect(result.active.count == 1)
    }

    @Test("completed meetup appears only in past bucket regardless of my status")
    func pastBucket() {
        let accepted = makeParticipation(meetupStatus: "completed", myStatus: "accepted")
        let arrived  = makeParticipation(meetupStatus: "completed", myStatus: "arrived")
        let result = filter([accepted, arrived])
        #expect(result.past.count == 2)
        #expect(result.invited.isEmpty)
        #expect(result.active.isEmpty)
    }

    @Test("cancelled meetup does not appear in any bucket")
    func cancelledExcluded() {
        let p = makeParticipation(meetupStatus: "cancelled", myStatus: "accepted")
        let result = filter([p])
        #expect(result.invited.isEmpty)
        #expect(result.active.isEmpty)
        #expect(result.past.isEmpty)
    }

    @Test("expired active meetup moves to past bucket")
    func expiredActiveMovesToPast() {
        let p = makeParticipation(
            myStatus: "accepted",
            startsAt: Date().addingTimeInterval(-8 * 3600),
            endsAt: Date().addingTimeInterval(-4 * 3600)
        )
        let result = filter([p])
        #expect(result.invited.isEmpty)
        #expect(result.active.isEmpty)
        #expect(result.past.count == 1)
    }

    @Test("expired invite moves to past bucket")
    func expiredInviteMovesToPast() {
        let p = makeParticipation(
            myStatus: "invited",
            startsAt: Date().addingTimeInterval(-8 * 3600),
            endsAt: Date().addingTimeInterval(-4 * 3600)
        )
        let result = filter([p])
        #expect(result.invited.isEmpty)
        #expect(result.active.isEmpty)
        #expect(result.past.count == 1)
    }

    @Test("target-arrival meetup moves to past when recap-ready")
    func targetArrivalRecapReadyMovesToPast() {
        let p = makeParticipation(
            myStatus: "accepted",
            targetArrivalAt: Date().addingTimeInterval(-2 * 3600),
            startsAt: Date().addingTimeInterval(-3 * 3600),
            endsAt: Date().addingTimeInterval(2 * 3600)
        )
        let result = filter([p])
        #expect(result.invited.isEmpty)
        #expect(result.active.isEmpty)
        #expect(result.past.count == 1)
    }

    @Test("mixed participations are distributed correctly")
    func mixedDistribution() {
        let participations = [
            makeParticipation(myStatus: "invited"),
            makeParticipation(myStatus: "accepted"),
            makeParticipation(meetupStatus: "completed", myStatus: "arrived"),
            makeParticipation(meetupStatus: "cancelled", myStatus: "accepted"),
        ]
        let result = filter(participations)
        #expect(result.invited.count == 1)
        #expect(result.active.count == 1)
        #expect(result.past.count == 1)
    }
}
