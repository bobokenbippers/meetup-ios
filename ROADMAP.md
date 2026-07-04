# Roadmap

Tracks what's in progress, what's next, and future ideas. Items in "Up Next" are milestone gaps that need to close before the app is shippable. Items below that are captured for consideration when the time is right.

---

## Milestone Status

| Milestone | Status | Notes |
|---|---|---|
| M1 — Auth | ✅ Done | Sign in with Apple, profile creation, display name capture |
| M2 — Friends | ✅ Mostly done | Add/remove friend, contacts, DMs, realtime inbox, and DM pushes work; friend-request pushes remain a follow-up |
| M3 — Meetups + Dashboard | ✅ Mostly done | Create, invite, accept/decline, share links, realtime, map, ETA labels, photos, games, and recap basics are in |
| M4 — Live Location | ✅ Mostly done | Battery-aware tiering, motion-aware ETA, OpenRouteService routing, and Stop Sharing are in; real-world drain still needs measurement |
| M5 — Punctuality + Notifications | ✅ Mostly done | ETA labels, late coloring, RSVP/event pushes, and late-punishment flow are in; "leave now" timing still needs field validation |
| M6 — Polish / Live Activities | ⚠️ Partial | Stop Sharing, routing polish, bill realtime, and camera capture are in; Live Activities and privacy audit log remain |
| M7 — TestFlight | ⚠️ In progress | Manual TestFlight workflow exists; current docs/notes being refreshed for the next beta |
| M8 — Mapbox Turn-by-Turn | 🔜 Deferred | Google/Apple Maps handoff is good enough for v1 |

---

## Up Next

Things that should happen before the next broader TestFlight push.

### TestFlight release readiness (M7)

The manual TestFlight workflow is in place. Before inviting more testers, keep the release story tight and make sure the merged build is green.

- Confirm CI and CodeQL are green on the latest `main`
- Update `CHANGELOG.md` with tester-facing notes
- Trigger the manual `TestFlight` workflow from GitHub Actions with `confirm_upload=YES`
- Smoke test on a real device with at least two accounts

*Needs: GitHub Actions green + manual TestFlight workflow run.*

---

### Venmo / PayPal settle-up links

Bill totals per person are computed across receipts. The next useful bill-flow improvement is a one-tap payment handoff from each settle-up row.

- Add optional Venmo/PayPal handle fields to profiles or bill participants
- Generate payment links with amount, recipient, and meetup note
- Fall back cleanly when no handle is available
- Add tests for URL encoding and amount formatting

*Needs: profile/payment-handle data model decision before implementation.*

---

### Privacy controls + audit log (M6)

Stop Sharing now gives users an in-meetup location cutoff. The remaining trust feature is an audit trail that shows when sensitive sharing starts, stops, and clears.

- Add an `audit_log` table and RLS policies
- Log location sharing start, stop, clear, and meetup completion events
- Surface recent privacy events in Settings or profile

*Needs: schema + RLS + small Settings surface.*

---

## Meetup Recap

**Recap polish**

The recap surface exists and can summarize arrivals, bills, photos, and late-punishment moments. The remaining work is making it feel like a shareable memory instead of a plain summary.

- Add editable notes/memories after completion
- Add a share card/export for the group recap
- Tighten empty states when a meetup had no photos, bills, or late arrivals

*Needs: UX polish and manual testing across completed meetup states.*

---

## Billing — Multiple Receipts

**Shipped; next polish**

Multiple receipts, receipt thumbnails, camera/photo capture, realtime bill sync, and roll-up totals are now in the app. The next billing step is settlement.

- Add Venmo/PayPal handoff links from settle-up rows
- Add better guidance when people have unclaimed shared items
- Smoke test bill realtime with two devices during an active meetup

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

## Unplanned / Misc

*(Drop one-liners here as they come up)*
