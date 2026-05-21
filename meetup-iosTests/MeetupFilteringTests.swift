import Testing
import Foundation
@testable import meetup_ios

@Suite("Meetup list filtering")
struct MeetupFilteringTests {

    private func makeMeetup(status: String = "active") -> Meetup {
        Meetup(
            id: UUID(),
            hostId: UUID(),
            destinationName: "Test Place",
            destinationAddress: nil,
            destinationLat: 0,
            destinationLng: 0,
            targetArrivalAt: nil,
            startsAt: Date(),
            endsAt: Date().addingTimeInterval(7200),
            status: status,
            shareToken: UUID().uuidString,
            createdAt: Date(),
            category: nil
        )
    }

    private func makeParticipation(meetupStatus: String = "active", myStatus: String) -> MyParticipation {
        MyParticipation(status: myStatus, meetup: makeMeetup(status: meetupStatus))
    }

    // Mirrors the filtering logic in MeetupsListView
    private func filter(_ participations: [MyParticipation]) -> (
        invited: [MyParticipation],
        active: [MyParticipation],
        past: [MyParticipation]
    ) {
        let invited = participations.filter { $0.status == "invited" && $0.meetup.status == "active" }
        let active  = participations.filter { $0.status != "invited" && $0.meetup.status == "active" }
        let past    = participations.filter { $0.meetup.status != "active" && $0.meetup.status != "cancelled" }
        return (invited, active, past)
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
