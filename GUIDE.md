# Meetup Tracker — Your Guide

The friendly companion doc. Read this when you want to know *what's happening* without wading through implementation details. Pair it with `IMPLEMENTATION.md` when you actually sit down to build.

---

## What You're Building

A meetup-aware navigation app for iOS.

You and friends are meeting at a bar at 1pm. You open the app, drop a pin on the bar, set "be there by 1pm," and invite three friends. They accept and start sharing their location for this meetup only. Everyone sees a dashboard:

- A map with everyone's position
- Each person's ETA and the route they're taking
- A colored tile per person — green for on time, red for "Sarah will be 12 min late"
- Smart push notifications: "Leave in 5 min to make it on time"

When everyone arrives, sharing automatically stops. That's the whole product.

---

## The Stack in Plain English

| Layer | What it does | What we're using |
|---|---|---|
| iOS app | What users see | SwiftUI |
| Auth | "Who are you?" | Sign in with Apple |
| Backend | "Where is everyone?" | Supabase (managed Postgres + realtime + auth) |
| Routing logic | "What's Sarah's ETA?" | Python service (FastAPI) calling Mapbox |
| Maps | The map view | Apple's MapKit (free, native) |
| Navigation | Turn-by-turn | Open in Apple Maps for v1 (deep link) |
| Push notifications | "Sarah will be late" | Apple Push Notification service (APNs) |

**Why Supabase:** It's managed Postgres + realtime updates + auth in one box. Replaces what would otherwise be 4–5 services. Free tier handles your first thousand users.

**Why Python on the backend:** It's fast to write, plays well with Apple/Mapbox APIs, and FastAPI gives you auto-generated API docs that the iOS app can use to generate type-safe API client code.

---

## The Build, Milestone by Milestone

Each milestone is roughly one weekend of focused work. Don't skip ahead — auth has to be solid before friends, friends before meetups, meetups before live data.

### M1 — Auth Working End-to-End *(1 weekend)*

**You'll know it works when:** You tap "Sign in with Apple" in your iOS app, do Face ID, and your name shows up in the Supabase dashboard.

What's happening: setting up the foundation. Apple Developer account, Supabase project, Xcode project, Sign in with Apple wired through to a database row. No features yet, just plumbing.

The bug to watch for: Apple sends the user's name *only on the first ever login*. If you don't capture it then, it's gone forever. The implementation plan handles this.

### M2 — Friends *(1 weekend)*

**You'll know it works when:** You can search for another user, send a friend request, they accept, and you both see each other in your friends list.

What's happening: building the social graph. Phone-based friend lookup with mutual accept. Push notifications for incoming requests. Block/report scaffolding (you'll fill it in later but the data model needs to support it from day one).

### M3 — Meetups + Dashboard *(2 weekends)*

**You'll know it works when:** You can create a meetup with a destination and target time, invite friends, and see them as gray "invited" tiles on a dashboard. They can accept and the tile turns green.

What's happening: the core meetup primitive. No live location yet — the dashboard is static, just showing who's accepted. Pick destination on a map, pick a time, send invites, see responses. Also: shareable invite links so people can join via SMS without already having the app.

### M4 — Live Location *(2 weekends)*

**You'll know it works when:** You and a friend can both have an active meetup open and see each other moving on the map in real time, with ETAs that update as you move.

What's happening: this is the heart of the app. Background GPS, smart battery management, WebSocket-style updates flowing through Supabase Realtime, server-side ETA computation calling Mapbox. The hardest weekend; expect debugging.

The bug to watch for: WebSockets drop constantly on mobile (tunnels, wifi handoffs, backgrounded apps). The implementation plan includes a "snapshot on reconnect" pattern that fixes this — make sure you build it from the start, not after.

### M5 — Punctuality + Smart Notifications *(1 weekend)*

**You'll know it works when:** During an active meetup with a target time, late participants show red tiles with "12 min late," and people who haven't left yet get pushed "Leave in 5 min" notifications.

What's happening: turning the app from a passive tracker into something useful. The compute pipeline is the same; you're just adding state machines on top of it. This is the weekend that makes the app feel magical.

### M6 — Polish, Privacy, Live Activities *(1–2 weekends)*

**You'll know it works when:** During an active meetup, your iPhone's lock screen and Dynamic Island show a live "Sarah 8 min, Mike arrived" widget. Privacy controls work end-to-end (one-tap stop sharing, audit log, block users).

What's happening: making it shippable. Privacy controls are non-negotiable for an app in this category. Live Activities are the polish that makes the app feel native.

### M7 — TestFlight & Real Use *(ongoing)*

**You'll know it's ready for App Store when:** You and 5–10 friends have run at least 20 real meetups. Battery drain is acceptable. Edge cases (poor GPS, parking garages, last-minute declines) are handled.

What's happening: catching the bugs you can't catch alone. Don't think about App Store submission until this milestone is solid.

### M8 — Mapbox Turn-by-Turn *(v2, post-launch)*

**Defer this.** For v1, "Open in Apple Maps" is a perfectly good navigation handoff. Most users will tap it and not notice they left your app. Adding Mapbox Navigation SDK is the most fiddly part of the project and doesn't differentiate the product. Ship without it.

---

## What's Going to Be Hard

Be honest with yourself about these:

**Background location on iOS.** Apple is strict. You'll get rejected from the App Store if you ask for "Always" location permission upfront without strong justification. The plan asks for "When In Use" by default and only escalates to "Always" when the user joins or hosts an active meetup, with a clear in-context explanation.

**Battery drain.** A naive "stream GPS at 1Hz" implementation will kill the user's battery and your app's reputation. The plan has tiered update strategies (60s when stationary, 10s when driving) and aggressive throttling. Expect to tune this in M7 with real use.

**Privacy and abuse.** A live-location app can be a stalking tool in the wrong hands. The plan treats privacy controls as day-one requirements: per-meetup time-boxed sharing only, one-tap stop, no location history visible to other participants, full audit log. Don't bolt these on later.

**Solo testing.** You cannot meaningfully test this app by yourself. Have at least one friend on TestFlight from M4 onward.

---

## Costs

Be prepared for:

- **$99/year** Apple Developer Program (required, no alternative)
- **$0** for everything else until you have real users (Supabase free tier, Mapbox free tier, Apple's MapKit and APNs are free)
- **$25/month** Supabase Pro plan when you outgrow the free tier (probably 3–6 months in if the app takes off)

Total realistic cost for the first 6 months: ~$50, almost entirely Apple's annual fee.

---

## Decisions You Already Made (Recorded Here So You Don't Re-Litigate)

These were settled in earlier conversations. Listed so future-you remembers why:

- **Sign in with Apple, no credentials stored.** OAuth-style — Apple handles auth, we just store an opaque ID. We never see passwords.
- **Find My data is not accessible.** Apple has no public API. The app runs its own location sharing.
- **Backend separated from frontend.** REST API + WebSocket so Android and web can hang off the same backend later.
- **Postgres database, yes.** Just an API endpoint won't work — you need persistent state.
- **Punctuality coloring.** Red = late, with hysteresis so the tile doesn't flash colors as ETAs jitter.
- **Mapbox over self-hosted routing.** Self-hosting OSRM/Valhalla is a trap for a solo build.
- **Supabase over self-hosted Postgres+Redis.** Saves weeks of plumbing for a solo build.
- **Apple Maps deep-link for v1, Mapbox Navigation SDK for v2.** Defer the complex integration.

---

## What This Doc Is *Not*

This doc tells you what's being built and why. For *how* to build each piece — actual commands, code, schemas, file paths — see `IMPLEMENTATION.md`.

If you ever feel lost, come back here. If you're sitting at the keyboard and need to know what to type, go to the implementation plan.

---

## Quick Glossary

**APNs** — Apple Push Notification service. The official way to send push notifications to iOS devices.

**Background location** — iOS's permission to track GPS while the app isn't open. Different rules from regular location.

**Bundle ID** — Your app's unique identifier in Apple's ecosystem. Looks like `com.yourname.meetup`.

**Geofence** — A virtual circle around a coordinate. "When Sarah enters this geofence, mark her as arrived."

**Hysteresis** — The trick that prevents UI from flickering between states. You only change state if the new value is meaningfully past the threshold AND has held for a few seconds.

**JWT (JSON Web Token)** — A signed string that proves "this user is who they say they are." Apple gives us one, we verify it, we issue our own.

**MapKit** — Apple's free, native maps framework. What the dashboard map will use.

**Mapbox** — Third-party maps and routing service. Used for ETA computation and (eventually) turn-by-turn navigation.

**PostGIS** — A Postgres extension that adds geographic types and queries (find points within X meters, etc.).

**Realtime / WebSocket** — A persistent connection that lets the server push updates to the client without the client asking. Used for live location updates.

**RLS (Row-Level Security)** — Postgres's built-in way of saying "only the meetup host and participants can see this row." Replaces a lot of authorization code.

**Silent push** — A push notification that doesn't show anything on screen but wakes the app briefly to do work (like grabbing a fresh location).

**SwiftUI** — Apple's modern UI framework. What the iOS app will be written in.
