# Repository Guidelines

## Project Structure & Module Organization

This repo contains the Squad Brunch iOS app. The Xcode project is `meetup-ios.xcodeproj`; app code lives in `meetup-ios/`.

- `meetup-ios/Models/`: `Codable` domain structs. Keep explicit `CodingKeys` for Supabase snake_case columns.
- `meetup-ios/Services/`: Supabase, location, contacts, notifications, receipts, billing, and photos.
- `meetup-ios/ViewModels/`: app-wide observable state such as auth and settings.
- `meetup-ios/Views/`: SwiftUI screens and reusable UI.
- `meetup-ios/Assets.xcassets/`: app icon, accent colors, and bundled assets.
- `meetup-iosTests/`: Swift Testing unit tests.
- `meetup-iosUITests/`: XCTest UI tests and screen objects.
- `supabase/migrations/` and `supabase/functions/`: database changes and Edge Functions.
- `fastlane/`: signing and TestFlight delivery.

## Build, Test, and Development Commands

Open the app in Xcode with `open meetup-ios.xcodeproj`.

```bash
xcodebuild -resolvePackageDependencies -project meetup-ios.xcodeproj
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios -configuration Debug -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project meetup-ios.xcodeproj -scheme meetup-ios -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO test
bundle exec fastlane ios beta
```

Use the first command after dependency changes. Build and test mirror CI. `fastlane ios beta` signs, archives, and uploads to TestFlight; it requires App Store Connect and Match secrets.

## Coding Style & Naming Conventions

Use SwiftUI-first implementations and avoid UIKit unless required. Follow existing four-space indentation, one primary type per file, and descriptive names such as `MeetupService`, `BillComputeTotalsTests`, and `RSVPInviteCard`. Prefer `@Observable`, `NavigationStack`, `.task`, and `foregroundStyle()` patterns already present in the app. Keep UI colors in `Utils/AppColors.swift`.

## Testing Guidelines

Unit tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) in `meetup-iosTests/`. UI tests use XCTest in `meetup-iosUITests/` with screen objects under `meetup-iosUITests/Screens/`. Add focused tests for parsing, billing math, formatting, filtering, and lifecycle logic. Run `xcodebuild ... test` before opening a PR; use Xcode's Test Navigator for individual tests.

## Commit & Pull Request Guidelines

Recent history uses short conventional prefixes, especially `fix:` and `feat:`. Write commits like `fix: prevent receipt quantity collapse` or `feat: add meetup photo gallery`.

PRs should include a concise description, issue or feature context, test results, and screenshots or recordings for UI changes. Note Supabase migrations, Edge Function changes, signing changes, or privacy-sensitive behavior.

Before merging any PR, rebase the PR branch onto the latest `main`, resolve conflicts there, rerun required checks, and use squash merge only. Do not use regular merge commits or GitHub's "Rebase and merge" path for PRs.

## Security & Configuration Tips

Do not commit local credentials, provisioning files, or generated secrets. Keep Supabase schema changes in `supabase/migrations/` and update implementation docs when behavior changes. Sign in with Apple and push notifications may require a real device or configured simulator/account.
