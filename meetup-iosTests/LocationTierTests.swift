import Testing
import CoreLocation
@testable import meetup_ios

@Suite("LocationTier")
struct LocationTierTests {

    // MARK: - uploadInterval

    @Test("stationary uploads every 60s")
    func stationaryInterval() {
        #expect(LocationTier.stationary.uploadInterval == 60)
    }

    @Test("walking uploads every 20s")
    func walkingInterval() {
        #expect(LocationTier.walking.uploadInterval == 20)
    }

    @Test("driving uploads every 15s")
    func drivingInterval() {
        #expect(LocationTier.driving.uploadInterval == 15)
    }

    @Test("nearDestination uploads every 10s")
    func nearDestinationInterval() {
        #expect(LocationTier.nearDestination.uploadInterval == 10)
    }

    // MARK: - forContext proximity override

    @Test("within 500m always returns nearDestination regardless of motion")
    func proximityOverridesMotion() {
        #expect(LocationTier.forContext(distanceToDestination: 499, motionMode: .stationary) == .nearDestination)
        #expect(LocationTier.forContext(distanceToDestination: 499, motionMode: .driving)    == .nearDestination)
        #expect(LocationTier.forContext(distanceToDestination: 0,   motionMode: .unknown)    == .nearDestination)
    }

    @Test("beyond 500m uses motion mode")
    func motionModeBeyond500m() {
        #expect(LocationTier.forContext(distanceToDestination: 501, motionMode: .stationary) == .stationary)
        #expect(LocationTier.forContext(distanceToDestination: 501, motionMode: .walking)    == .walking)
        #expect(LocationTier.forContext(distanceToDestination: 501, motionMode: .cycling)    == .walking)
        #expect(LocationTier.forContext(distanceToDestination: 501, motionMode: .driving)    == .driving)
        #expect(LocationTier.forContext(distanceToDestination: 501, motionMode: .unknown)    == .walking)
    }

    @Test("exactly 500m is NOT nearDestination (threshold is strict < 500)")
    func exactly500m() {
        #expect(LocationTier.forContext(distanceToDestination: 500, motionMode: .stationary) == .stationary)
    }

    // MARK: - isLocationValid guards

    @Test("valid location passes both guards")
    func validLocation() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        #expect(LocationManager.isLocationValid(loc))
    }

    @Test("accuracy > 200m fails accuracy guard")
    func poorAccuracy() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: 201,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        #expect(!LocationManager.isLocationValid(loc))
    }

    @Test("fix older than 90s fails staleness guard")
    func staleLocation() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date(timeIntervalSinceNow: -91)
        )
        #expect(!LocationManager.isLocationValid(loc))
    }

    @Test("negative horizontalAccuracy (invalid fix) fails guard")
    func invalidAccuracy() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        #expect(!LocationManager.isLocationValid(loc))
    }

    @Test("fix clearly within 90s old still passes")
    func exactlyAtStalenessEdge() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date(timeIntervalSinceNow: -89)
        )
        #expect(LocationManager.isLocationValid(loc))
    }

    @Test("accuracy exactly 200m passes")
    func exactlyAtAccuracyEdge() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: 200,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        #expect(LocationManager.isLocationValid(loc))
    }
}
