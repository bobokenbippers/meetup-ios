import Foundation
import CoreLocation
import CoreMotion
import MapKit
import Observation

enum MotionMode {
    case stationary, walking, cycling, driving, unknown
}

enum LocationTier: Equatable {
    case stationary, walking, driving, nearDestination

    var uploadInterval: TimeInterval {
        switch self {
        case .stationary:       return 60
        case .walking:          return 20
        case .driving:          return 15
        case .nearDestination:  return 10
        }
    }

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .stationary:       return kCLLocationAccuracyHundredMeters
        case .walking:          return kCLLocationAccuracyNearestTenMeters
        case .driving:          return kCLLocationAccuracyNearestTenMeters  // same as walking — 10m is sufficient for route tracking
        case .nearDestination:  return kCLLocationAccuracyBest
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .stationary:       return 50
        case .walking:          return 15
        case .driving:          return 20
        case .nearDestination:  return 5
        }
    }

    static func forContext(distanceToDestination: CLLocationDistance, motionMode: MotionMode) -> LocationTier {
        if distanceToDestination < 500 { return .nearDestination }
        switch motionMode {
        case .stationary:           return .stationary
        case .walking, .cycling:    return .walking
        case .driving:              return .driving
        case .unknown:              return .walking
        }
    }
}

@Observable
final class LocationManager: NSObject {
    static let shared = LocationManager()

    private let clManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.squadbrunch.motionqueue"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()
    private(set) var trackingMeetup: Meetup?
    private var uploadTask: Task<Void, Never>?
    private var expiryTimer: Timer?
    private(set) var location: CLLocation?
    private var motionMode: MotionMode = .unknown
    private(set) var currentTier: LocationTier = .stationary

    var isTracking: Bool { trackingMeetup != nil }

    override private init() {
        super.init()
        clManager.delegate = self
        applyTier(.stationary)
    }

    func requestPermission() {
        clManager.requestWhenInUseAuthorization()
    }

    func startTracking(meetup: Meetup) {
        if trackingMeetup?.id == meetup.id { return }
        trackingMeetup = meetup
        if isExpired(meetup: meetup) { stopTracking(); return }
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
        clManager.startUpdatingLocation()
        startMotionUpdates()
        startUploadLoop()
        scheduleExpiryTimer()
    }

    func stopTracking() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        trackingMeetup = nil
        clManager.stopUpdatingLocation()
        clManager.allowsBackgroundLocationUpdates = false
        motionManager.stopActivityUpdates()
        uploadTask?.cancel()
        uploadTask = nil
    }

    private func isExpired(meetup: Meetup) -> Bool {
        guard let target = meetup.targetArrivalAt else { return false }
        return Date() > target.addingTimeInterval(5400)
    }

    private func scheduleExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let meetup = self.trackingMeetup else { return }
            if self.isExpired(meetup: meetup) { self.stopTracking() }
        }
    }

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        // Deliver on a background queue so classifying motion doesn't block UI.
        motionManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let self, let activity else { return }
            let mode: MotionMode
            if activity.automotive      { mode = .driving }
            else if activity.walking    { mode = .walking }
            else if activity.running    { mode = .walking }
            else if activity.cycling    { mode = .cycling }
            else if activity.stationary { mode = .stationary }
            else                        { mode = .unknown }
            DispatchQueue.main.async { self.motionMode = mode }
        }
    }

    private func startUploadLoop() {
        uploadTask?.cancel()
        uploadTask = Task {
            while !Task.isCancelled {
                await uploadLocationAndETA()
                await checkArrived()
                recalculateTier()
                do {
                    try await Task.sleep(for: .seconds(currentTier.uploadInterval))
                } catch {
                    return
                }
            }
        }
    }

    private func recalculateTier() {
        guard let meetup = trackingMeetup, let loc = location else { return }
        let dest = CLLocation(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
        let newTier = LocationTier.forContext(distanceToDestination: loc.distance(from: dest), motionMode: motionMode)
        if newTier != currentTier {
            currentTier = newTier
            applyTier(newTier)
        }
    }

    private func applyTier(_ tier: LocationTier) {
        clManager.desiredAccuracy = tier.desiredAccuracy
        clManager.distanceFilter = tier.distanceFilter
    }

    private func uploadLocationAndETA() async {
        guard let meetup = trackingMeetup, let loc = location else { return }
        guard LocationManager.isLocationValid(loc) else { return }
        let dest = CLLocationCoordinate2D(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
        let eta = await calculateETA(from: loc.coordinate, to: dest)
        try? await MeetupService.shared.updateMyLocation(
            meetupId: meetup.id,
            lat: loc.coordinate.latitude,
            lng: loc.coordinate.longitude,
            bearing: loc.course >= 0 ? loc.course : nil,
            etaSeconds: eta
        )
    }

    private func checkArrived() async {
        guard let meetup = trackingMeetup, let loc = location else { return }
        let dest = CLLocation(latitude: meetup.destinationLat, longitude: meetup.destinationLng)
        guard loc.distance(from: dest) < 50 else { return }
        try? await MeetupService.shared.updateParticipantStatus(meetupId: meetup.id, status: "arrived")
        stopTracking()
    }

    private func calculateETA(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = .automobile
        return try? await MKDirections(request: request).calculate().routes.first.map { Int($0.expectedTravelTime) }
    }

    static func isLocationValid(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy > 0 &&
        location.horizontalAccuracy <= 200 &&
        location.timestamp.timeIntervalSinceNow >= -90
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
