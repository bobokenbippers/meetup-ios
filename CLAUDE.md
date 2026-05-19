# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

iOS app ("Squad Brunch" / Meetup Tracker) — friends share live location and ETA toward a chosen destination for the duration of a single meetup. SwiftUI app talking directly to Supabase (Postgres + Auth + Realtime). No custom backend yet — the Python/FastAPI service described in `GUIDE.md` / `IMPLEMENTATION.md` has not been built; the iOS client talks to Supabase directly and uses Apple's `MKDirections` for ETA.

Build target: iOS 26.4, Swift 5.0, Xcode 26+ (uses `Map` content builder, `.glass` / `.glassProminent` button styles, `GlassEffectContainer`, `@Observable`, `realtimeV2`). Bundle ID `gautamlgtm.meetup-ios`.

## Build / Run

There is no test target and no SwiftPM manifest at the repo root — the only entry point is the Xcode project.

```bash
# Resolve SPM deps (once / after pulling)
xcodebuild -resolvePackageDependencies -project meetup-ios.xcodeproj

# Build for simulator
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Clean
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios clean
```

Day-to-day work happens in Xcode (`open meetup-ios.xcodeproj`). Sign in with Apple requires a real device or a simulator signed into an Apple ID — it does not work in a fresh, signed-out simulator.

The `ios-swift-skills:ios-debugger-agent` skill is the right tool for building, running on simulator, and capturing logs.

## Architecture

MVVM-flavored SwiftUI with global service singletons. All data lives in Supabase; the app holds essentially no local state beyond a cached `Profile` in `UserDefaults`.

### Layout
- `meetup-ios/Models/` — `Profile`, `Meetup`, `MeetupParticipant`, `MyParticipation`. Plain `Codable` structs; every property uses explicit `CodingKeys` to map snake_case Postgres columns. Match this when adding new columns.
- `meetup-ios/Services/`
  - `SupabaseManager` — singleton wrapping `SupabaseClient`. **Supabase URL and anon publishable key are hardcoded here** (`Services/SupabaseManager.swift`). This is the single client config point.
  - `MeetupService` — all Postgres CRUD for meetups + participants. Encodes inserts as nested local structs with explicit CodingKeys (don't use `[String: Any]` — the Supabase Swift encoder is strict).
  - `LocationManager` — singleton; `CLLocationManager` + `MKDirections` for ETA, uploads every 30s via `MeetupService.updateMyLocation`. Currently uses `kCLLocationAccuracyHundredMeters` and `distanceFilter = 50`. The tiered/battery-aware strategy described in `IMPLEMENTATION.md` is **not yet implemented**.
- `meetup-ios/ViewModels/AuthViewModel.swift` — `@Observable`, owns `session` and `profile`. Subscribes to `supabase.auth.authStateChanges`. Caches profile in `UserDefaults` under `cachedProfile` for instant UI on cold launch.
- `meetup-ios/Views/` — SwiftUI screens. App root gates on `(session, profile, phoneE164)`: `SignInView` → `ProgressView` while loading → `ProfileSetupView` (phone capture) → `HomeView` (TabView).

### Auth flow (Sign in with Apple → Supabase)
1. `SignInView` requests `[.fullName, .email]` scopes.
2. `AuthViewModel.signInWithApple` calls `supabase.auth.signInWithIdToken(provider: .apple, idToken:)`.
3. Apple sends the user's name **only on the first ever login** — `signInWithApple` writes it into `profiles.display_name` immediately. If this step is skipped, the name is gone forever. Don't refactor it into a "we'll fill it in later" path.
4. A DB trigger (`handle_new_user`, defined in `IMPLEMENTATION.md` §M1.1) creates the `profiles` row when `auth.users` is inserted. `AuthViewModel.loadProfile` falls back to inserting a row itself if the trigger row hasn't appeared yet.
5. Phone number is captured in `ProfileSetupView`; format is hardcoded `+1` + 10 US digits. Friend lookup (`find_user_by_phone` RPC) uses this exact E.164 form.

### Realtime
`MeetupDashboardView` opens a `realtimeV2` channel `meetup-<id>` subscribed to `postgres_changes` on `meetup_participants` and re-runs `listParticipants` on every event. Be careful with the channel lifecycle — `realtimeTask` is cancelled in `.onDisappear` and the channel is explicitly removed; do not leak channels by skipping that teardown.

### Location tracking
`LocationManager.startTracking(meetup:)` enables `allowsBackgroundLocationUpdates` and starts a 30s upload loop. `MeetupDashboardView` starts tracking when the user's status is `accepted` and stops on disappear. Background location requires the `location` entry in `Info.plist` `UIBackgroundModes` (already present). When adding `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription`, edit `meetup-ios/Info.plist` directly — the Xcode build does not auto-generate Info.plist.

### Push notifications
`AppDelegate` requests `UNUserNotificationCenter` authorization at launch and writes the APNs token into `profiles.apns_token` once registered. The update is silently a no-op if the `profiles` row doesn't exist yet (e.g. before sign-in) — that's intentional, since the token is re-registered on every launch.

## Database

There are no migration files in this repo. The full schema, RLS policies, triggers, and RPCs live in `IMPLEMENTATION.md` and must be applied manually in the Supabase SQL editor. When adding/changing tables:

1. Edit `IMPLEMENTATION.md` to keep the canonical schema in sync.
2. Run the SQL against Supabase.
3. Update the matching `Codable` model in `meetup-ios/Models/`.
4. Update RLS policies — RLS is on for every table; an iOS query that returns empty results without an error almost always means a missing/wrong policy.

Participant `status` is a plain text column with values `"invited" | "accepted" | "declined" | "arrived"`. Treat it as a sum type — there is no Swift enum yet.

## Supabase Swift SDK

The Xcode project depends on `supabase-swift` via remote SPM (`git@github.com:supabase/supabase-swift.git`). The `supabase-swift/` directory at the repo root is a **separate, unrelated checkout of that SDK for reference reading** — it is not a submodule and is not built by the app. Don't edit it expecting changes to take effect, and don't add it to the Xcode project.

## Companion docs

- `GUIDE.md` — product overview, milestone roadmap (M1–M8), and locked-in design decisions. Read before proposing scope changes.
- `IMPLEMENTATION.md` — detailed step-by-step build plan with SQL, code snippets, and acceptance criteria per milestone. The source of truth for schema and the planned backend.
- `PRIVACY_POLICY.md` — current published privacy policy text.

Milestones already done: M1 (auth), most of M3 (meetup creation, dashboard, accept/decline, basic realtime). M2 friends UI and M4 robust live-location/battery work are partially done at best — check the code, not the doc, before claiming a milestone is complete.

## SwiftUI smoothness

After touching any SwiftUI view, invoke the `swiftui-smoothness-auditor` skill (`.claude/agents/swiftui-smoothness-auditor.md`). Key invariants to watch for without running the auditor:
- Never start realtime subscriptions in `.onAppear` — fold into `.task` so the lifecycle is tied to the task and cancellation propagates naturally.
- Never use `try? await Task.sleep(...)` in loops — swallowing `CancellationError` prevents clean task teardown; use `do { try await } catch { return }`.
- Guard `@Observable` array reassignment: if `MeetupParticipant` (which is `Equatable`) loads the same data, skip the write to prevent wasted SwiftUI diffing.
- `DispatchQueue.main.asyncAfter` bypasses Swift actor isolation — use `Task { try? await Task.sleep(for:); ... }` instead.
- Don't put duplicate `.onChange` handlers on both a control and its parent view.
- Prefer `.clipShape(RoundedRectangle(cornerRadius:))` over deprecated `.cornerRadius()`.
