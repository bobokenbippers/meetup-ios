import Foundation
import CoreLocation
import CoreMotion
import MapKit
import Observation

enum MotionMode {
    case stationary, walking, cycling, driving, unknown
}

enum GoogleRouteTravelMode: String {
    case drive = "DRIVE"
    case walk = "WALK"
    case bicycle = "BICYCLE"
    case transit = "TRANSIT"

    var googleMapsURLValue: String {
        switch self {
        case .drive:   return "driving"
        case .walk:    return "walking"
        case .bicycle: return "bicycling"
        case .transit: return "transit"
        }
    }

    static func forMotionMode(_ motionMode: MotionMode) -> GoogleRouteTravelMode {
        switch motionMode {
        case .driving:
            return .drive
        case .walking:
            return .walk
        case .cycling:
            return .bicycle
        case .stationary, .unknown:
            return .transit
        }
    }
}

enum OpenRouteServiceProfile: String {
    case drivingCar = "driving-car"
    case cyclingRegular = "cycling-regular"
    case footWalking = "foot-walking"

    static func forMotionMode(_ motionMode: MotionMode) -> OpenRouteServiceProfile {
        switch motionMode {
        case .walking:
            return .footWalking
        case .cycling:
            return .cyclingRegular
        case .stationary, .driving, .unknown:
            return .drivingCar
        }
    }
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
        case .driving:          return kCLLocationAccuracyNearestTenMeters
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

    /// The CLActivityType hint that best describes this tier's movement pattern.
    /// Helps iOS tune satellite/cell handoffs for power efficiency.
    var clActivityType: CLActivityType {
        switch self {
        case .stationary:       return .other
        case .walking:          return .fitness
        case .driving:          return .automotiveNavigation
        case .nearDestination:  return .automotiveNavigation
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
    @ObservationIgnored private var lastPublishedLocationAt: Date?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var motionMode: MotionMode = .unknown {
        didSet {
            guard motionMode != oldValue else { return }
            handleMotionModeChange()
        }
    }
    private(set) var currentTier: LocationTier = .stationary

    // Continuation used to interrupt the upload-loop sleep when the tier changes.
    // When non-nil, resuming it causes the current sleep to return immediately so
    // the loop can restart with the new interval.
    private var tierChangeContinuation: CheckedContinuation<Void, Never>?

    var isTracking: Bool { trackingMeetup != nil }
    var googleMapsDirectionsMode: String {
        GoogleRouteTravelMode.forMotionMode(motionMode).googleMapsURLValue
    }

    override private init() {
        super.init()
        clManager.delegate = self
        authorizationStatus = clManager.authorizationStatus
        applyTier(.stationary)
    }

    func requestPermission() {
        clManager.requestWhenInUseAuthorization()
    }

    /// Fetch a single current fix when we're not in an active tracking session,
    /// so features like nearby-event suggestions have a coordinate to query with.
    /// No-op once we already have a location (tracking loop or a prior one-shot).
    func requestOneShotLocation() {
        guard location == nil else { return }
        let status = clManager.authorizationStatus
        authorizationStatus = status
        switch status {
        case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            clManager.requestLocation()
        case .denied, .restricted:
            return
        @unknown default:
            return
        }
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
        Task { try? await PrivacyAuditLogService.shared.log(.locationSharingStarted, meetup: meetup) }
    }

    /// Refresh the cached destination for an in-flight tracking session after the host
    /// edits the meetup location, so the next ETA upload routes to the new coordinates.
    func updateTrackedDestination(meetup: Meetup) {
        guard trackingMeetup?.id == meetup.id else { return }
        trackingMeetup = meetup
    }

    func stopTracking() {
        let stoppedMeetup = trackingMeetup
        expiryTimer?.invalidate()
        expiryTimer = nil
        trackingMeetup = nil
        clManager.stopUpdatingLocation()
        clManager.allowsBackgroundLocationUpdates = false
        motionManager.stopActivityUpdates()
        uploadTask?.cancel()
        uploadTask = nil
        if let stoppedMeetup {
            Task { try? await PrivacyAuditLogService.shared.log(.locationSharingStopped, meetup: stoppedMeetup) }
        }
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

    // Called on the main actor whenever motionMode changes so the CLManager
    // hints and tier are updated immediately without waiting for the loop sleep.
    private func handleMotionModeChange() {
        guard isTracking else { return }
        recalculateTier()
    }

    private func startUploadLoop() {
        uploadTask?.cancel()
        uploadTask = Task {
            while !Task.isCancelled {
                await uploadLocationAndETA()
                await checkArrived()
                recalculateTier()

                // Sleep for the current tier's interval, but allow early wake-up if
                // the tier changes (e.g. from 60 s stationary to 10 s nearDestination).
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    tierChangeContinuation = continuation
                    Task {
                        do {
                            try await Task.sleep(for: .seconds(currentTier.uploadInterval))
                        } catch {
                            // Task was cancelled — fall through so the outer loop exits.
                        }
                        // Resume the continuation if it hasn't already been resumed by a
                        // tier change.  Using a swap so double-resume is impossible.
                        let cont = tierChangeContinuation
                        tierChangeContinuation = nil
                        cont?.resume()
                    }
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
            // Wake the sleeping upload loop so it picks up the new interval immediately.
            wakeUploadLoop()
        }
    }

    /// Interrupt the current sleep cycle so the upload loop restarts with the new tier's interval.
    private func wakeUploadLoop() {
        let cont = tierChangeContinuation
        tierChangeContinuation = nil
        cont?.resume()
    }

    private func applyTier(_ tier: LocationTier) {
        clManager.desiredAccuracy = tier.desiredAccuracy
        clManager.distanceFilter = tier.distanceFilter
        clManager.activityType = tier.clActivityType
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
        if let openRouteETA = await OpenRouteService.shared.calculateETA(
            from: origin,
            to: destination,
            motionMode: motionMode
        ) {
            return openRouteETA
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = motionMode == .walking || motionMode == .cycling ? .walking : .automobile
        return try? await MKDirections(request: request).calculate().routes.first.map { Int($0.expectedTravelTime) }
    }

    static func isLocationValid(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy > 0 &&
        location.horizontalAccuracy <= 200 &&
        location.timestamp.timeIntervalSinceNow >= -90
    }
}

private struct OpenRouteService {
    static let shared = OpenRouteService()

    private var apiKey: String? {
        AppEnvironment.current.value(for: "OPENROUTESERVICE_API_KEY")
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        motionMode: MotionMode
    ) async -> Int? {
        guard let apiKey else { return nil }

        let profile = OpenRouteServiceProfile.forMotionMode(motionMode).rawValue
        guard let url = URL(string: "https://api.openrouteservice.org/v2/matrix/\(profile)") else { return nil }

        let body = OpenRouteServiceMatrixRequest(
            locations: [
                [origin.longitude, origin.latitude],
                [destination.longitude, destination.latitude]
            ],
            sources: ["0"],
            destinations: ["1"],
            metrics: ["duration"]
        )

        guard let httpBody = try? JSONEncoder().encode(body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = httpBody

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let matrixResponse = try? JSONDecoder().decode(OpenRouteServiceMatrixResponse.self, from: data),
              let duration = matrixResponse.durations.first?.compactMap({ $0 }).first
        else {
            return nil
        }

        return Int(duration.rounded())
    }
}

private struct OpenRouteServiceMatrixRequest: Encodable {
    let locations: [[Double]]
    let sources: [String]
    let destinations: [String]
    let metrics: [String]
}

private struct OpenRouteServiceMatrixResponse: Decodable {
    let durations: [[Double?]]
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last,
              shouldPublishLocation(newLocation)
        else { return }
        location = newLocation
        lastPublishedLocationAt = newLocation.timestamp
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard location == nil else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.requestLocation()
    }

    // requestLocation() reports failures here; swallow them — callers degrade gracefully
    // when `location` stays nil (e.g. nearby-event suggestions just hide their section).
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func shouldPublishLocation(_ newLocation: CLLocation) -> Bool {
        guard LocationManager.isLocationValid(newLocation) else { return false }
        guard let current = location, let lastPublishedLocationAt else { return true }

        let elapsed = newLocation.timestamp.timeIntervalSince(lastPublishedLocationAt)
        let moved = newLocation.distance(from: current)
        let minimumMove = max(10, currentTier.distanceFilter * 0.5)

        return elapsed >= 5 || moved >= minimumMove
    }
}
