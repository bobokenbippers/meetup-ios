# Battery-Aware Location Tiering — Design Spec

**Date:** 2026-05-21
**Status:** Approved
**Milestone:** M4 — Live Location

---

## Problem

`LocationManager` currently runs a flat 30s upload loop at `kCLLocationAccuracyHundredMeters` with a 50m distance filter regardless of whether the user is stationary, walking, driving, or nearly at the destination. This wastes battery when the user hasn't moved and under-samples when they're close to arriving.

---

## Decision

Use `CMMotionActivityManager` (CoreMotion) to detect motion state and drive a tiered upload loop. A single adaptive loop reads `currentTier` each iteration to determine sleep duration and CLLocationManager settings. Proximity to destination overrides the motion tier when the user is within 500m.

---

## Tier Model

| Tier | Trigger condition | Upload interval | `desiredAccuracy` | `distanceFilter` |
|---|---|---|---|---|
| `.stationary` | CoreMotion: stationary | 60s | `kCLLocationAccuracyHundredMeters` | 50m |
| `.walking` | CoreMotion: walking or cycling | 20s | `kCLLocationAccuracyNearestTenMeters` | 15m |
| `.driving` | CoreMotion: automotive | 15s | `kCLLocationAccuracyNearestTenMeters` | 20m |
| `.nearDestination` | Distance to destination < 500m | 10s | `kCLLocationAccuracyBest` | 5m |

`nearDestination` overrides all CoreMotion states. Once within 500m, the tightest settings are always used regardless of motion mode.

**Arrived detection:** when current location is within 50m of destination, call a new `MeetupService.updateParticipantStatus(meetupId:status:)` method (see below) with `status: "arrived"`, then call `stopTracking()`. This fires at most 10s after crossing the 50m threshold (one `.nearDestination` cycle).

---

## Architecture

All changes are confined to `meetup-ios/Services/LocationManager.swift` and `meetup-ios/Info.plist`. No other files change.

### New components inside LocationManager

**`LocationTier` enum** — four cases, each carrying `uploadInterval: TimeInterval`, `desiredAccuracy: CLLocationAccuracy`, `distanceFilter: CLLocationDistance`.

**`CMMotionActivityManager`** — started alongside `CLLocationManager` when tracking begins. Activity callbacks update `currentTier` (unless overridden by proximity).

**`currentTier: LocationTier`** — exposed as a property compatible with `@Observable` so `MeetupDashboardView` can optionally react (e.g., show "Almost there!"). Not required by this task — UI changes are out of scope.

### Upload loop (adaptive)

```
startUploadLoop():
  while !cancelled:
    uploadLocationAndETA()       // guarded — see below
    checkArrived()               // stop tracking if <50m
    recalculateTier()            // motion state + proximity
    applyTierToManager()         // update desiredAccuracy + distanceFilter
    sleep(currentTier.uploadInterval)
```

`recalculateTier()` always runs even when an upload was skipped, so the tier stays current during GPS-dark periods.

### Upload guards

Both must pass before an upload is sent:

1. **Accuracy guard:** `loc.horizontalAccuracy <= 200m` — skips uploads when GPS is poor (underground, parking garage, basement).
2. **Staleness guard:** `loc.timestamp` is within the last 90 seconds — prevents uploading a cached pre-tunnel fix after the user resurfaces at a different location.

**Subway scenario:** user boards → goes underground → GPS fixes stop → `location` holds last surface fix. Staleness guard catches this within 90s. When user resurfaces at a new station, iOS delivers a fresh fix → both guards pass → position updates within one driving-tier cycle (≤15s). Friends see the user frozen at the boarding station during the gap, then snap to the correct exit point on recovery. No stale teleport from a cached fix.

---

## Info.plist

Add one key:

```xml
<key>NSMotionUsageDescription</key>
<string>Used to adapt location updates to save battery during active meetups.</string>
```

CoreMotion's `CMMotionActivityManager` requires this string. iOS shows a one-time permission prompt on M-series iPhones. `CMMotionActivityManager.isActivityAvailable()` is always `true` on the app's minimum target (iOS 26.4).

---

## MeetupService addition

A new method is required for arrived detection:

```swift
func updateParticipantStatus(meetupId: UUID, status: String) async throws
```

Implementation follows the same pattern as `acceptMeetup` / `declineMeetup` — a single `.update(["status": status])` filtered to the current user's row in `meetup_participants`.

---

## What does NOT change

- `MeetupService.updateMyLocation` call signature
- `MeetupDashboardView` start/stop tracking calls
- `MeetupParticipant` model
- Realtime subscription logic
- Any view other than the optional `currentTier` observation hook

---

## Acceptance Criteria

- [ ] Stationary device uploads at ~60s intervals; walking device at ~20s; driving at ~15s
- [ ] Within 500m of destination, interval drops to ~10s regardless of motion state
- [ ] User arriving within 50m of destination: status flips to `"arrived"` and tracking stops automatically
- [ ] No upload is sent when `horizontalAccuracy > 200m`
- [ ] No upload is sent when the location fix is older than 90s
- [ ] Subway scenario: no stale position uploaded after an underground gap; position snaps to surfacing point within one driving-tier cycle
- [ ] `NSMotionUsageDescription` present in Info.plist
- [ ] Battery drain during a 30-min active meetup remains ≤5% on the tracking device (per M4 spec)
