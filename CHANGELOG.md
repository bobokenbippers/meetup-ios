# Changelog

## [Unreleased] - 2026-07-04
### TestFlight Notes
This beta is about real-world meetup reliability: location sharing is more battery-aware, Stop Sharing clears your live location, invite/RSVP pushes are wired, directions use your current travel mode, and bills now stay in sync while multiple people claim receipt items.

Please test:
- Create a meetup, invite a friend, and confirm invite/RSVP push notifications arrive.
- Join an active meetup, start sharing location, then tap Stop Sharing and confirm your location disappears from the dashboard.
- Start directions while walking, driving, and cycling if possible; confirm Google Maps opens in the expected mode.
- Open Split Bill on two devices, add multiple receipts, claim/unclaim items, and confirm both screens update without leaving the view.
- Capture one receipt with Document Scanner and one with the Camera option; confirm thumbnails and parsed items appear.
- Open a completed meetup recap and confirm arrivals, photos, and bill totals look right.
- Send text/photo DMs and confirm unread counts and push routing still work.
- Open Settings and use Send Feedback to report anything weird.

### Added
- Battery-aware location tiering that adapts update interval, accuracy, and activity type based on motion and destination proximity.
- Push notifications for core meetup events, including invites and RSVP changes.
- OpenRouteService ETA support with Google Routes and MapKit fallback.
- Stop Sharing control on the meetup dashboard that stops location updates and clears the user's live location from Supabase.
- Multi-receipt bill flow with receipt thumbnails, explicit Camera capture, and realtime sync for receipts, items, and claims.
- Routing-mode tests for Google Maps handoff values.
- Truth or Dare squad game inside meetups: start a session from the dashboard Game button, pick Normal or Spicy prompts, and play in a realtime lobby. A server-decided full-screen coin flip (heads = truth, tails = dare) with a slow-motion settle and haptics picks each player's fate; dares require an in-app camera photo proof that shows in the shared game feed, truths are answered out loud, and passes land on the end-of-game chicken scoreboard. Backed by `game_sessions`/`game_players`/`game_turns`/`game_prompts` tables, SECURITY DEFINER RPCs, and Supabase Realtime.
- Friend direct messages with a Messages tab, inbox, chat threads, realtime updates, unread counts, and push routing.
- Text and photo messages between accepted friends, backed by the new `message-photos` storage bucket.
- Delete support for a user's own direct messages.
- Supabase DM backend: conversations, messages, read-state RPCs, RLS policies, storage policies, and `push-new-message` edge function.
- Settings beta feedback action with a prefilled email that includes app version, user id, iOS version, and device model.
- Shareable meetup invite links now use a web fallback page that redirects into the app for installed beta testers.
- Profile photo upload from Settings, backed by the new `profile-photos` storage bucket and `profiles.avatar_url`.

### Changed
- Google Maps directions now use the user's current motion mode instead of always launching the same travel mode.
- Bill views refresh in place when another participant edits receipts, item claims, or bill data.
- Received meetup invites now show the sender with a `From <name>` line.
- Meetup dashboard invite responses are ordered `Yes`, `Maybe`, `No`.
- Message threads now include an explicit `Messages` back button.
- Meetup share sheets now include readable invite text plus the web invite URL.

### Fixed
- Added missing Contacts, Camera, and Photos privacy usage strings required for TestFlight/App Review builds.
- Permission prompts now stay inside onboarding/settings instead of firing location and notification prompts immediately on launch; existing push-authorized users still re-register their APNs token on launch.
- App Review: changed onboarding pre-permission copy so the location prompt uses a neutral Continue action.
- App Review: made live background location sharing an explicit Start/Stop action on active meetup dashboards.
- Location sharing can now be explicitly stopped during a meetup instead of only ending when the view disappears.
- Bill item claims no longer require leaving and reopening Split Bill to see another tester's changes.
- Truth or Dare: players are no longer trapped in a dead game. Any player in a session can now end it (not just the original starter), so a soft-locked game started by someone else can be cleared by anyone in it.
- Truth or Dare: an active game with no playable turn now shows a "This game stalled" screen with an End Game / Close action instead of spinning forever.
- Truth or Dare: abandoned sessions are auto-retired by a janitor cron — lobbies that sit over 6h without reaching 2 players, and active games with no turn activity for 12h — so they stop showing as "live" in everyone's games list.
- Knicks theme: active food/brunch meetup cards now use a gradient of Knicks Blue into a darker shade of the same blue instead of ending in bright burnt orange, so the white card title reads clearly (9.6:1 contrast) and the card leans Knicks blue instead of being mostly orange. Stays on the official Knicks palette.
- Meetup dashboard action buttons (Directions, Split Bill, Game) no longer wrap or hyphenate onto two lines now that the row holds three buttons.
- Invitees can see the meetup host/sender in the participant roster after accepting an invite.
- Missing host participant rows are backfilled so older meetups can render the inviter.
- Settings feedback now sends to `gautam.pappu@utexas.edu` instead of the unregistered `support@squadbrunch.app` address.
- The invite fallback page no longer points to a fake App Store listing.
- The `join-meetup` Edge Function is configured as public so shared invite links can open from Messages or a browser.
- Event suggestions can request location correctly after authorization by adding required iOS location usage strings and a one-shot location fetch.
- Event suggestions no longer disappear when location permission is pending or unavailable; the Meetups tab now shows a clear location prompt or empty state.
- Event suggestion API configuration is now included in the app target build settings so release builds can read it reliably.
- Settings → Sync Contacts now actually requests contact permission, reports sync status, and gates contact suggestions throughout the app.
- Friend requests now insert under the canonical friendship RLS policy regardless of UUID ordering.
- Destination search now guards Google Places configuration so typing a meetup location cannot crash when Places is unavailable.
- Destination search now falls back to Apple MapKit so meetup location suggestions still work if Google Places is unavailable.
- Chat photo selection now reliably prepares the selected image before sending and resizes uploads for faster delivery.
- Chat photo failures now show inline recovery instead of silent broken/loading states, and message photo links stay valid longer.
- Open chat threads now refresh while you stay in the conversation, even if realtime misses a message event.
- Event suggestions now keep the section visible with a retry action when the event provider or network request fails.
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
