# Distribution Readiness

Use this as the pre-TestFlight gate for Squad Brunch. The goal is to catch install, permission, push, signing, and App Review problems before a build reaches testers.

## Code Gate

- `Info.plist` includes usage strings for every protected API the app touches:
  - Location while in use and background location
  - Motion
  - Contacts
  - Camera
  - Photo library
- Permission prompts are contextual:
  - Onboarding requests location and notifications after the user taps Allow.
  - Settings can re-request or route blocked users to iOS Settings.
  - App launch only re-registers remote notifications when the user has already granted notification permission.
- Push capability is present in `meetup-ios/meetup-ios.entitlements` with production APNs for TestFlight.
- Background modes include active-meetup location sharing and remote notification delivery.
- App Store export compliance is declared with `ITSAppUsesNonExemptEncryption = false` because the app only uses standard/exempt platform networking.

## Build Gate

Run these before opening a release PR:

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
xcodebuild -resolvePackageDependencies -project meetup-ios.xcodeproj
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" CODE_SIGNING_ALLOWED=NO -only-testing:meetup-iosTests test
```

Run the TestFlight lane only after the PR is reviewed and merged:

```bash
bundle exec fastlane ios beta
```

## Manual Smoke Test

- Fresh install, sign in with Apple, complete profile setup, complete onboarding.
- Accept notification and location prompts from onboarding.
- Create a meetup, invite a second device, open the invite link from Messages, and land in the joined meetup.
- Background and kill the app, then trigger invite/RSVP/message pushes and confirm tapping each push opens the right screen.
- Start active location sharing, background the app, and confirm ETA/location updates continue for the active meetup only.
- Stop sharing and confirm the dashboard clears live location.
- Send a photo DM, upload a meetup photo, scan or capture a receipt, and submit Truth or Dare proof to verify all photo/camera permission strings.
- Toggle push notifications off/on in Settings and confirm the device token refreshes after turning them back on.

## External Gate

- GitHub Actions secrets exist for `TICKETMASTER_API_KEY`, `OPENROUTE_APP_KEY`, Match, and App Store Connect.
- Apple Developer App ID has Sign in with Apple, Push Notifications, and Background Modes enabled.
- App Store Connect metadata, screenshots, privacy nutrition labels, support URL, and privacy policy URL are filled in.
- Supabase migrations and edge functions are deployed to the production project before shipping the matching TestFlight build.
