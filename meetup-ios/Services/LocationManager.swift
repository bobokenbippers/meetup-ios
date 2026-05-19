import Foundation
import CoreLocation
import MapKit

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
                try? await Task.sleep(for: .seconds(30))
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
        let sourceLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        request.source = MKMapItem(location: sourceLocation, address: nil)
        request.destination = MKMapItem(location: destLocation, address: nil)
        request.transportType = .automobile
        return try? await MKDirections(request: request).calculate().routes.first.map { Int($0.expectedTravelTime) }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
