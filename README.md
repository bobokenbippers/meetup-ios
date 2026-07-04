# Squad Brunch

A live location sharing and meetup coordination app for iOS.

## What it does

- **Create meetups** — set a destination (MapKit search), arrival time, category, and invite friends
- **Live location** — background GPS updates every 30s; ETAs calculated via OpenRouteService with Google Routes and MapKit fallback; location data wiped from DB when meetup ends
- **People** — find friends by name or phone number from your contacts
- **Bill splitting** — scan a receipt with Apple Vision, claim items per person, see totals
- **Sign in with Apple** — auth via Supabase

## Stack

- SwiftUI + `@Observable` MVVM
- Supabase (Postgres + Auth + Realtime) — no custom backend
- MapKit for search; OpenRouteService with Google Routes and MapKit fallback for ETA
- Apple Vision for receipt scanning
- Fastlane + GitHub Actions → TestFlight

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| CI | Every PR + push to `main` | Builds + runs unit tests (no signing) |
| TestFlight | Manual workflow dispatch | Signs, archives, uploads to TestFlight after `confirm_upload=YES` |

## Local development

1. Clone the repo
2. Open `meetup-ios.xcodeproj` in Xcode
3. Set your own bundle ID and development team in project settings
4. Add `Config.xcconfig` with your Supabase URL and anon key (see `IMPLEMENTATION.md` for schema)
5. Add `Secrets.xcconfig` from `Secrets.example.xcconfig`; set `APP_ENV` to include `OPENROUTESERVICE_API_KEY`. For GitHub Actions, add the same key as the repository secret `OPENROUTE_APP_KEY`.
6. Run on simulator or device

## Project structure

```
meetup-ios/
├── Models/          # Codable structs with explicit CodingKeys
├── Services/        # Supabase CRUD, LocationManager, SupabaseManager
├── Views/           # SwiftUI screens
└── Assets.xcassets/ # App icon, colors
```

See `IMPLEMENTATION.md` for the full database schema and architecture notes.
