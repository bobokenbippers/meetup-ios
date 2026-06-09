# Changelog

## [Unreleased] - 2026-06-09
### TestFlight Notes
Friend DMs are here: open Messages to chat with accepted friends, send text/photo messages, and delete your own messages. Meetup invites now show who sent them, RSVP buttons are ordered Yes/Maybe/No, chat threads have a clearer back button, Settings includes a prefilled beta feedback email, event suggestions stay visible while asking for location, and the app no longer flashes the meetup screen before auth finishes.

Please test:
- Create a meetup, invite a friend, and confirm the invite says who sent it.
- Open the meetup after accepting and confirm the host appears in the participant list.
- Send text and photo DMs both ways.
- Delete one of your own messages.
- Background the app and confirm DM push notifications open the right place.
- Open Settings and use Send Feedback to report anything weird.

### Added
- Friend direct messages with a Messages tab, inbox, chat threads, realtime updates, unread counts, and push routing.
- Text and photo messages between accepted friends, backed by the new `message-photos` storage bucket.
- Delete support for a user's own direct messages.
- Supabase DM backend: conversations, messages, read-state RPCs, RLS policies, storage policies, and `push-new-message` edge function.
- Settings beta feedback action with a prefilled email that includes app version, user id, iOS version, and device model.

### Changed
- Received meetup invites now show the sender with a `From <name>` line.
- Meetup dashboard invite responses are ordered `Yes`, `Maybe`, `No`.
- Message threads now include an explicit `Messages` back button.

### Fixed
- Invitees can see the meetup host/sender in the participant roster after accepting an invite.
- Missing host participant rows are backfilled so older meetups can render the inviter.
- Event suggestions can request location correctly after authorization by adding required iOS location usage strings and a one-shot location fetch.
- Event suggestions no longer disappear when location permission is pending or unavailable; the Meetups tab now shows a clear location prompt or empty state.
- Event suggestion API configuration is now included in the app target build settings so release builds can read it reliably.
- Chat photo selection now reliably prepares the selected image before sending and resizes uploads for faster delivery.
- Open chat threads now refresh while you stay in the conversation, even if realtime misses a message event.
- Auth startup no longer flashes the full meetup UI before Supabase finishes resolving the initial session.

---

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
