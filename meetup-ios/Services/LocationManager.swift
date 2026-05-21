import Foundation
import CoreLocation
import CoreMotion
import MapKit

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

final class LocationManager: NSObject {
    static let shared = LocationManager()

    private let clManager = CLLocationManager()
    private var trackingMeetup: Meetup?
    private var uploadTask: Task<Void, Never>?
    private(set) var location: CLLocation?

    override private init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        clManager.distanceFilter = 50
    }

    func requestPermission() {
        clManager.requestWhenInUseAuthorization()
    }

    func startTracking(meetup: Meetup) {
        if trackingMeetup?.id == meetup.id { return }
        trackingMeetup = meetup
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
        clManager.startUpdatingLocation()
        startUploadLoop()
    }

    func stopTracking() {
        trackingMeetup = nil
        clManager.stopUpdatingLocation()
        clManager.allowsBackgroundLocationUpdates = false
        uploadTask?.cancel()
        uploadTask = nil
    }

    private func startUploadLoop() {
        uploadTask?.cancel()
        uploadTask = Task {
            while !Task.isCancelled {
                await uploadLocationAndETA()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
    }

    private func uploadLocationAndETA() async {
        guard let meetup = trackingMeetup, let loc = location else { return }
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
