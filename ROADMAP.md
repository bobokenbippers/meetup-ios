# Roadmap

Tracks what's in progress, what's next, and future ideas. Items in "Up Next" are milestone gaps that need to close before the app is shippable. Items below that are captured for consideration when the time is right.

---

## Milestone Status

| Milestone | Status | Notes |
|---|---|---|
| M1 — Auth | ✅ Done | Sign in with Apple, profile creation, display name capture |
| M2 — Friends | ⚠️ Partial | Add/remove friend works; push notifications for requests not wired |
| M3 — Meetups + Dashboard | ✅ Mostly done | Create, invite, accept/decline, realtime, map, ETA labels |
| M4 — Live Location | ⚠️ Partial | 30s upload loop works; tiered battery strategy not implemented |
| M5 — Punctuality + Notifications | ⚠️ Partial | ETA labels + late coloring work; push delivery not wired |
| M6 — Polish / Live Activities | ❌ Not started | No Dynamic Island, no audit log, no one-tap stop sharing UI |
| M7 — TestFlight | ❌ Not started | |
| M8 — Mapbox Turn-by-Turn | 🔜 Deferred | "Open in Apple Maps" is good enough for v1 |

---

## Up Next

Things that need to be built before the app is ready for real-world use.

### Battery-aware location tiering (M4)

`LocationManager` currently uploads every 30s at `kCLLocationAccuracyHundredMeters` with no awareness of motion state. The tiered strategy described in `IMPLEMENTATION.md` §M4 is not yet implemented.

- Switch to `CLActivityType.automotiveNavigation` when moving
- Stationary: 60s interval, `kCLLocationAccuracyHundredMeters`
- Walking/moving: 15–20s interval, `kCLLocationAccuracyNearestTenMeters`
- Within ~500m of destination: 10s interval, highest accuracy
- Tighten `distanceFilter` as proximity decreases

*Needs: updates to `LocationManager.startTracking` and the upload loop.*

---

### Push notifications for meetup events (M5)

APNS token is saved to `profiles.apns_token` on every launch, but nothing sends pushes. Key events that need delivery:

- **Invite received** → push to invitee
- **Accept/decline** → push to host
- **"Leave now"** → push when ETA math says the user needs to depart to arrive on time
- **Arrived** → push to host when a participant marks arrived

*Needs: Supabase Edge Function or database trigger + APNS delivery via the saved token.*

---

### Friend request push notifications (M2)

Same gap as meetup notifications — token exists, delivery doesn't.

- Incoming friend request → push to recipient
- Request accepted → push to requester

*Needs: same Edge Function pattern as meetup push.*

---

### Live Activities — Dynamic Island + Lock Screen (M6)

During an active meetup, the Dynamic Island and Lock Screen should show a live summary: ETAs and arrival status for each participant. Users shouldn't need to open the app to see who's on their way.

*Needs: `ActivityKit` framework, a Widget Extension target, and a `MeetupLiveActivityAttributes` type pushed from `MeetupDashboardView`.*

---

### Privacy controls + one-tap stop sharing (M6)

- **Stop Sharing button** — stops `LocationManager` uploads and clears the participant's location columns in Supabase. Currently the app only stops uploads on `onDisappear`; there's no in-meetup "I'm done sharing" affordance.
- **Audit log** — `IMPLEMENTATION.md` §M6 describes an `audit_log` table. Needs schema + RLS + a read surface (Settings or profile).

---

### Shareable invite links (M3 gap)

GUIDE.md calls this out for M3 but it was never built. SMS invites let someone join a meetup without already having the app installed.

- Universal Links config in Apple Developer portal + `apple-app-site-association`
- Deep link handler in `meetup_iosApp.swift` (`.onOpenURL`)
- Join-meetup flow: open link → install app if needed → land on dashboard

---

## Meetup Recap

**Post-event summary page**

After a meetup ends (`meetup.status == "completed"`), show a recap screen:
- Who came (accepted → arrived participants)
- Individual arrival times vs. target time
- Total spent (sum of all bills attached to this meetup)
- Shared photos from the event
- Notes / memories (free-text, editable after the fact)

*Needs: `meetup_photos` table; `notes` column on `meetups`; recap view gated on completed status. `meetup_participants.arrived_at` may already exist — confirm schema before adding.*

---

## Billing — Multiple Receipts

**More than one bill per meetup**

Allow attaching multiple receipts to a single meetup (e.g., dinner + drinks at different venues). Each receipt splits independently; totals roll up to the meetup recap.

- `bills` table already exists — add a `meetup_id` foreign key
- `BillView` currently handles one bill per session; needs a bill list + "Add another receipt" button
- Roll up totals per person across all bills for the recap

---

## Gamification

**Reward system for punctuality**

Track punctuality across meetups using `meetup_participants.arrived_at` vs. `meetups.target_time`. Surface stats and rewards:

- **Points / medals** — award for on-time or early arrivals; track a late-arrival count per user
- **Medal tiers** — e.g., "Always Early", "Usually On Time", "Fashionably Late"
- **Celebration animation** — confetti or similar on arrival (state already exists in `MeetupDashboardView`)
- **Profile stats** — visible to friends on the People tab

*Needs: `arrival_records` table or computed view from `meetup_participants`; profile stats columns; animation layer.*

---

## Payment Integration

**Venmo / PayPal deep links from bill summary**

Bill totals per person are already computed. The natural next step: generate a Venmo or PayPal deep link from the "you owe X" row so settling up is one tap.

- `venmo://paycharge?txn=pay&recipients=<username>&amount=<total>&note=<meetup_name>`
- Low priority — works well as a post-launch addition once the bill flow is stable.

---

## Unplanned / Misc

*(Drop one-liners here as they come up)*
