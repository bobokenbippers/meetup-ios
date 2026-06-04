# Changelog

## [2.0.0] - 2026-05-20
### Added
- Full UI redesign: coral accent color (`#FF6B47`) throughout the app
- Category gradient cards on meetup rows (brunch/food → red-orange, drinks → purple, coffee → green, others → glass)
- Status pills on meetup rows: Invited (yellow), Live (green), Late (red)
- New empty state on meetups list with radial glow and "Plan a Meetup" CTA button
- Dashboard greeting header with personalized name + people count
- Glass destination card on dashboard with countdown timer
- New participant pins on map: avatar circle + callout bubble showing name and colored ETA
- Blue pulsing dot for "you" on the map
- Glass bottom panel on dashboard (22pt top corners) with drag handle and colored participant rows
- People tab: glass search bar, colored avatar cards
- Tab bar tinted coral on active selection
- `PhoneFormatter` utility extracted for reusable phone formatting logic
- Unit test suite: 37 tests covering `PhoneFormatter`, `ReceiptParser`, `BillService`, meetup filtering (Swift Testing framework)
- XCUITest suite: 26 UI tests covering all main flows — sign-in, meetups tab, create meetup form, people tab, settings tab

### Fixed
- Destination text field now responds instantly on first tap (contacts store IPC moved off main thread)
- SwiftUI smoothness: fixed task cancellation propagation, redundant state writes, actor isolation issues
- People tab no longer shows auth error alert during UI testing

---

## [1.0.6] - 2026-05-19
### Added
- App description line on meetups list header: "Track your squad's live location and ETA to the meetup spot."

### Fixed
- App icon alpha channel rejection on App Store Connect
- Removed EXIF/iTXt metadata chunks from app icons causing upload failures
- Removed unreferenced dark icon variant from asset catalog
- Animations now fire correctly (wrapped state changes with `withAnimation`)
- Suppressed `CancellationError` alerts when switching tabs
- Destination search subtitles use `shortAddress` format

---

## [1.0.5] - 2026-05-18
### Added
- Partiful-style animations throughout the app (spring transitions, staggered list entries)
- Category badge displayed on meetup list rows and dashboard
- 12-hour three-column wheel time picker (replaces 24-hour picker)

---

## [1.0.4] - 2026-05-17
### Added
- Bill splitting feature: scan receipt with camera, assign items to participants, view per-person totals
- On-device receipt parsing using Apple Vision framework
- `BillView`, `BillService`, `Bill`, `BillItem`, `BillItemClaim` models
- Camera permission for receipt scanning

---

## [1.0.3] - 2026-05-16
### Added
- Meetup categories: create meetups with Squad Brunch, Squad Happy Hour, Squad Kickback, or custom category
- Past meetups grouped by category on the list view
- Category badge shown on meetup rows and dashboard
# CI triggered 2026-06-04T12:59:58Z
