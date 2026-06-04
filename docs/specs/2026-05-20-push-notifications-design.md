# Push Notifications — Design Spec

**Date:** 2026-05-20  
**Status:** Ready for implementation

---

## Overview

Four notification events:

| Event | Delivery | Recipient |
|---|---|---|
| Meetup invite received | Remote push (Edge Function) | Invitee |
| Participant accepted/declined | Remote push (Edge Function) | Host |
| Participant arrived | Remote push (Edge Function) | Host (skip if host is the one arriving) |
| Leave-now alert | Local notification (on-device) | Self |

---

## Prerequisites — APNs Setup

Before the Edge Function can send pushes, the following must be configured.

**Step 1 — Generate an APNs key (if not already done)**
1. Apple Developer Portal → Certificates, Identifiers & Profiles → Keys
2. Create a new key, enable "Apple Push Notifications service (APNs)"
3. Download the `.p8` file (one-time download — save it)
4. Note the **Key ID** (10 chars) and your **Team ID** (top-right of the portal)

**Step 2 — Add secrets to Supabase Edge Functions**
In Supabase dashboard → Settings → Edge Functions → Secrets, add:

| Secret name | Value |
|---|---|
| `APNS_KEY` | Full contents of the `.p8` file |
| `APNS_KEY_ID` | 10-character key ID from Apple |
| `APNS_TEAM_ID` | 10-character team ID from Apple |
| `APNS_BUNDLE_ID` | `gautamlgtm.meetup-ios` |
| `APNS_ENV` | `sandbox` for dev/simulator, `production` for TestFlight/release |

---

## Remote Push Path

### Edge Function: `notify-participant`

Single function handles all three remote notification types by inspecting the webhook payload.

**Trigger:** Supabase database webhook on `meetup_participants`  
**Webhook events:** `INSERT`, `UPDATE`

**Logic:**

```
receive webhook payload (table, type, record, old_record)

if type == UPDATE:
  if old_record.status == new_record.status → SKIP (location update, not a status change)

determine notification type:
  INSERT                          → "invite"
  UPDATE, new status "accepted"   → "accepted"
  UPDATE, new status "declined"   → "declined"
  UPDATE, new status "arrived"    → "arrived"

determine recipient and actor:
  "invite"   → recipient = record.user_id (invitee), actor = meetups.created_by (host)
  "accepted" → recipient = meetups.created_by (host), actor = record.user_id (participant)
  "declined" → recipient = meetups.created_by (host), actor = record.user_id (participant)
  "arrived"  → recipient = meetups.created_by (host), actor = record.user_id (participant)
               SKIP if actor == recipient (host marked themselves arrived)

SKIP if actor == recipient (e.g. host invited themselves)

look up recipient's apns_token from profiles
  if null → SKIP (user has no push permission or token not yet registered)

build payload:
  - alert title + body (see Notification Copy below)
  - custom data: { meetup_id: "...", event: "invite"|"accepted"|"declined"|"arrived" }

POST to APNs HTTP/2 endpoint using JWT auth (ES256, signed with APNS_KEY)
  endpoint: api.sandbox.push.apple.com (sandbox) or api.push.apple.com (production)

on APNs 410 response (token no longer valid):
  clear profiles.apns_token for that user
```

**Database webhook setup** (Supabase dashboard → Database → Webhooks):
- Table: `meetup_participants`
- Events: Insert, Update
- HTTP POST to: `https://<project>.supabase.co/functions/v1/notify-participant`
- Include `Authorization: Bearer <service_role_key>` header

### Notification Copy

| Event | Title | Body |
|---|---|---|
| Invite | "New meetup invite" | "[Host name] invited you to [meetup name]" |
| Accepted | "[Name] is coming" | "[Name] accepted your invite to [meetup name]" |
| Declined | "[Name] can't make it" | "[Name] declined your invite to [meetup name]" |
| Arrived | "[Name] is here" | "[Name] has arrived at [meetup name]" |

All payloads include `meetup_id` in the APNs custom data so the app can navigate on tap.

---

## Leave-Now Path (on-device)

### Changes to `LocationManager`

**New state:**
```swift
private var scheduledLeaveAlerts: Set<UUID> = []
```

**After each ETA update in the upload loop:**
1. Guard: `meetup.targetTime != nil`
2. Guard: participant status is not `"arrived"`
3. Guard: `scheduledLeaveAlerts` does not already contain `meetup.id`
4. Compute departure buffer: if `currentETA >= minutesUntilTargetTime - 10` → fire alert
5. Schedule a `UNNotificationRequest` with `.timeInterval(1)` trigger (immediate)
6. Insert `meetup.id` into `scheduledLeaveAlerts` so it only fires once per meetup

**On `stopTracking()`:** remove any pending leave-now notifications via `UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:)` and clear `scheduledLeaveAlerts`.

**Known limitation:** If the app is force-quit during an active meetup, background location stops and this alert cannot fire. This is inherent to the on-device approach and acceptable for v1.

---

## iOS App Changes

### `AppDelegate` — add `UNUserNotificationCenterDelegate`

```swift
func application(_:didFinishLaunchingWithOptions:) {
    UNUserNotificationCenter.current().delegate = self  // ADD THIS
    // ... existing code unchanged
}

// Show banner + play sound even when app is in the foreground
func userNotificationCenter(_:willPresent:withCompletionHandler:) {
    completionHandler([.banner, .sound])
}

// Handle tap: post a notification so the right meetup opens
func userNotificationCenter(_:didReceive:withCompletionHandler:) {
    if let meetupId = response.notification.request.content.userInfo["meetup_id"] as? String {
        NotificationCenter.default.post(
            name: .openMeetup,
            object: nil,
            userInfo: ["meetup_id": meetupId]
        )
    }
    completionHandler()
}
```

### Deep-link to meetup on tap

`HomeView` (or `MeetupsListView`) listens for `.openMeetup` and navigates to the matching meetup dashboard. The meetup list already loads on appear — this just needs to trigger sheet presentation for the right meetup ID.

---

## Edge Cases

| Case | Handling |
|---|---|
| Location update triggers webhook | Skip in Edge Function: `old_record.status == new_record.status` |
| `apns_token` is null | Edge Function skips gracefully |
| Stale/invalid token (APNs 410) | Clear `profiles.apns_token` |
| Self-notification | Skip if actor_id == recipient_id |
| Host is the one who arrived | Skip "arrived" push (no one to notify) |
| No target time set | Skip leave-now computation |
| User status is already "arrived" | Skip leave-now |
| Leave-now fires multiple times | `scheduledLeaveAlerts` set, fires once per meetup |
| App force-quit during meetup | Leave-now won't fire (accepted limitation) |
| Foreground notification display | `willPresent` returns `.banner + .sound` |
| Multiple devices | Last registered token wins (acceptable for v1) |
| Duplicate webhook delivery | Results in duplicate push; acceptable for v1 |
| APNs sandbox vs production | Controlled by `APNS_ENV` secret |

---

## Files to Create / Modify

| File | Change |
|---|---|
| `supabase/functions/notify-participant/index.ts` | New Edge Function (create directory) |
| `meetup-ios/meetup_iosApp.swift` | Add `UNUserNotificationCenterDelegate`, set delegate |
| `meetup-ios/Services/LocationManager.swift` | Add leave-now scheduling logic |
| `meetup-ios/Views/HomeView.swift` | Listen for `.openMeetup` notification, navigate to dashboard |
| Supabase dashboard | Configure webhook + Edge Function secrets |
