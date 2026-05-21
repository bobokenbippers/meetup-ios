# Battery-Aware Location Tiering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat 30s upload loop in `LocationManager` with a CoreMotion-driven tiered strategy that adapts upload interval and GPS accuracy to motion state and proximity to destination, and automatically detects arrival.

**Architecture:** A `LocationTier` enum encodes the four tiers (stationary/walking/driving/nearDestination). `CMMotionActivityManager` updates a `motionMode` property; a `recalculateTier()` call in the upload loop picks the right tier from motion + proximity. Two upload guards (accuracy ≤200m, fix age ≤90s) silence uploads during GPS-denied gaps (subway, tunnels). Arrival is detected when the user gets within 50m of the destination.

**Tech Stack:** Swift 5, CoreLocation, CoreMotion (`CMMotionActivityManager`), MapKit (`MKDirections`), Supabase Swift SDK, Swift Testing

---

## File Map

| File | Action | What changes |
|---|---|---|
| `meetup-ios/Services/LocationManager.swift` | Modify | Full rewrite: add `LocationTier`, `MotionMode`, CoreMotion, adaptive loop, guards, arrived detection |
| `meetup-ios/Services/MeetupService.swift` | Modify | Add `updateParticipantStatus(meetupId:status:)` |
| `meetup-ios/Info.plist` | Modify | Add `NSMotionUsageDescription` |
| `meetup-iosTests/LocationTierTests.swift` | Create | Unit tests for tier selection and upload guards |

---

## Task 1: Add `LocationTier` and `MotionMode` enums with tests

**Files:**
- Modify: `meetup-ios/Services/LocationManager.swift`
- Create: `meetup-iosTests/LocationTierTests.swift`

- [ ] **Step 1: Add enums at the top of LocationManager.swift**

Replace the entire content of `meetup-ios/Services/LocationManager.swift` with:

```swift
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
```

> Note: the upload loop is still flat 30s at this point — the adaptive loop lands in Task 3. This step only adds the enums and `isLocationValid`.

- [ ] **Step 2: Create the test file**

Create `meetup-iosTests/LocationTierTests.swift`:

```swift
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

    @Test("fix exactly 90s old still passes")
    func exactlyAtStalenessEdge() {
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30, longitude: -97),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date(timeIntervalSinceNow: -90)
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
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests/LocationTierTests 2>&1 | grep -E "PASS|FAIL|error:|Build"
```

Expected: all 10 tests PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add meetup-ios/Services/LocationManager.swift meetup-iosTests/LocationTierTests.swift
git commit -m "Add LocationTier and MotionMode enums with unit tests"
```

---

## Task 2: Add `updateParticipantStatus` to MeetupService

**Files:**
- Modify: `meetup-ios/Services/MeetupService.swift`

- [ ] **Step 1: Find the right insertion point**

Open `meetup-ios/Services/MeetupService.swift` and locate the `decline` method (around line 174). Add the new method immediately after it:

```swift
    func updateParticipantStatus(meetupId: UUID, status: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }
        try await supabase
            .from("meetup_participants")
            .update(["status": status])
            .eq("meetup_id", value: meetupId)
            .eq("user_id", value: userId)
            .execute()
    }
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add meetup-ios/Services/MeetupService.swift
git commit -m "Add MeetupService.updateParticipantStatus for arrived detection"
```

---

## Task 3: Rewrite LocationManager with CoreMotion + adaptive loop

**Files:**
- Modify: `meetup-ios/Services/LocationManager.swift`

- [ ] **Step 1: Replace the full file**

Replace the entire content of `meetup-ios/Services/LocationManager.swift` with the following. This preserves the `LocationTier`, `MotionMode`, and `isLocationValid` from Task 1 and replaces the stub upload loop with the full adaptive implementation:

```swift
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
    private let motionManager = CMMotionActivityManager()
    private var trackingMeetup: Meetup?
    private var uploadTask: Task<Void, Never>?
    private(set) var location: CLLocation?
    private var motionMode: MotionMode = .unknown
    private(set) var currentTier: LocationTier = .stationary

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
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
        clManager.startUpdatingLocation()
        startMotionUpdates()
        startUploadLoop()
    }

    func stopTracking() {
        trackingMeetup = nil
        clManager.stopUpdatingLocation()
        clManager.allowsBackgroundLocationUpdates = false
        motionManager.stopActivityUpdates()
        uploadTask?.cancel()
        uploadTask = nil
    }

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            if activity.automotive      { self?.motionMode = .driving }
            else if activity.walking    { self?.motionMode = .walking }
            else if activity.running    { self?.motionMode = .walking }
            else if activity.cycling    { self?.motionMode = .cycling }
            else if activity.stationary { self?.motionMode = .stationary }
            else                        { self?.motionMode = .unknown }
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
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 3: Run all unit tests**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests 2>&1 | grep -E "PASS|FAIL|error:|Test Suite"
```

Expected: all tests PASS including the 10 `LocationTierTests`.

- [ ] **Step 4: Commit**

```bash
git add meetup-ios/Services/LocationManager.swift
git commit -m "Implement adaptive location tiering with CoreMotion and arrived detection"
```

---

## Task 4: Add `NSMotionUsageDescription` to Info.plist

**Files:**
- Modify: `meetup-ios/Info.plist`

- [ ] **Step 1: Add the key**

Open `meetup-ios/Info.plist`. Find any existing `<key>NS...UsageDescription</key>` entry (e.g. `NSLocationWhenInUseUsageDescription`) and add the new key/string pair immediately after its closing `</string>` tag:

```xml
<key>NSMotionUsageDescription</key>
<string>Used to adapt location updates to save battery during active meetups.</string>
```

- [ ] **Step 2: Build to confirm plist is valid**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add meetup-ios/Info.plist
git commit -m "Add NSMotionUsageDescription for CoreMotion permission"
```

---

## Task 5: Manual acceptance verification

No automated tests can cover the on-device behavior. Verify against the acceptance criteria from the spec using the iOS Simulator or a real device.

- [ ] **Step 1: Build and run on simulator**

Open `meetup-ios.xcodeproj` in Xcode and run on iPhone 17 Pro simulator (⌘R).

- [ ] **Step 2: Verify guard behavior with simulated poor GPS**

In Xcode's simulator, use **Features → Location → Custom Location** and set `horizontalAccuracy` to a high value by choosing a location far from any cell tower. Confirm in the Xcode console (add a `print` temporarily if needed) that `isLocationValid` returns `false` and uploads are skipped.

- [ ] **Step 3: Verify arrival detection**

In an active meetup, use **Features → Location → Custom Location** in the simulator and set coordinates to within 50m of the meetup's destination. Confirm in Supabase dashboard (`meetup_participants` table) that the participant's `status` flips to `"arrived"` and location updates stop.

- [ ] **Step 4: Run full unit test suite one final time**

```bash
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:meetup-iosTests 2>&1 | grep -E "PASS|FAIL|error:|Test Suite"
```

Expected: all tests pass.
