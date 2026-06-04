# Supermemory Integration — Design Spec

**Date:** 2026-05-21
**Status:** Approved

---

## Overview

Integrate [Supermemory](https://supermemory.ai) to give Squad Brunch persistent, searchable meetup memories. When a meetup completes, an auto-generated summary is stored to Supermemory scoped to the host user. Memories are surfaced in three places: a new Memories tab, the Create Meetup view (past venues as quick-picks), and the meetup recap screen.

---

## Architecture

### Approach

**iOS → Supabase Edge Functions → Supermemory SDK**

The Supermemory TypeScript SDK runs inside two Supabase Edge Functions. The iOS app calls these functions via the existing Supabase client (`functions.invoke`). The `SUPERMEMORY_API_KEY` lives in Supabase Edge Function secrets and never touches the iOS app.

No new Supabase tables. No new hosting infrastructure.

---

## Backend: Supabase Edge Functions

### `store-meetup-memory`

**Location:** `supabase/functions/store-meetup-memory/index.ts`

**Input:**
```json
{ "meetupId": "<uuid>", "userId": "<uuid>" }
```

**Behavior:**
1. Fetches the `meetups` row (venue name, target_time, status).
2. Fetches all `meetup_participants` for the meetup (display_name, status, arrived_at).
3. Fetches any attached `bills` (total amount).
4. Builds a plain-text memory string:

```
Meetup at [venue] on [date, time].
Attendees ([count]): [name1], [name2], [name3].
[X] arrived on time, [Y] arrived [Z] min late.
Total bill: $[amount] split [N] ways.
```

5. Calls `supermemory.add(content, { containerTag: "user_<userId>", metadata: { meetupId, venue, date } })`.
6. Returns `{ success: true, memoryId: "..." }`.

**Error:** Returns `{ success: false, error: "..." }` — never throws an unhandled 500.

---

### `search-memories`

**Location:** `supabase/functions/search-memories/index.ts`

**Input:**
```json
{ "userId": "<uuid>", "query": "optional search string" }
```

**Behavior:**
1. Calls `supermemory.search(query ?? "", { containerTag: "user_<userId>" })`.
2. Returns the list of memory objects with text + metadata.

**Output schema:**
```json
[
  {
    "id": "mem_...",
    "content": "Meetup at Josephine's on May 18...",
    "metadata": {
      "meetupId": "<uuid>",
      "venue": "Josephine's",
      "date": "2026-05-18T13:00:00Z"
    }
  }
]
```

**Error:** Returns empty array `[]` on failure — never throws an unhandled 500.

---

## iOS Layer

### `MemoryService.swift`

New singleton service in `meetup-ios/Services/`.

```swift
actor MemoryService {
    static let shared = MemoryService()

    func storeMemory(meetupId: UUID, userId: UUID) async
    func searchMemories(userId: UUID, query: String?) async throws -> [MeetupMemory]
}
```

- `storeMemory` calls `store-meetup-memory` via `SupabaseManager.shared.client.functions.invoke(...)`. Failures are caught and logged silently — the meetup completion flow is not blocked.
- `searchMemories` calls `search-memories` and decodes the JSON response into `[MeetupMemory]`. Throws on decode error; callers catch and fall back to `[]`.

---

### Data Model: `MeetupMemory`

```swift
struct MeetupMemory: Identifiable, Codable {
    let id: String       // Supermemory-assigned ID
    let content: String  // full memory text
    let venue: String    // from metadata
    let date: Date       // from metadata
    let meetupId: UUID   // from metadata
}
```

---

### `MeetupDashboardView` changes

- Gains a "Complete Meetup" button visible when the user is the host and meetup status is `"active"`.
- Auto-trigger consideration: if all `accepted` participants reach `status == "arrived"`, the button becomes prominent with a "Everyone's here — end meetup?" prompt.
- On completion:
  1. Calls `MeetupService.updateMeetupStatus(id:, status: "completed")`.
  2. Calls `MemoryService.shared.storeMemory(meetupId:, userId:)` (fire-and-forget, non-blocking).
  3. Navigates or dismisses the dashboard.

---

### `CreateMeetupView` changes

- On `.task`, calls `MemoryService.shared.searchMemories(userId:, query: nil)` to load past venues.
- Extracts unique venue names from the returned memories' metadata.
- Renders them as horizontally scrolling chips above the destination search field: tapping one pre-fills the destination text field.
- If the search fails or returns nothing, the chip row is hidden (no error shown).

---

### `MeetupMemoriesView` (new screen)

- `NavigationStack` with a `List` of `MeetupMemory` rows.
- Each row: venue name (bold), date (secondary), first line of `content` (tertiary, truncated to 2 lines).
- `TextField` at top for search. Debounced 400ms before calling `searchMemories(query:)`.
- Loading state: `ProgressView` shown while fetching.
- Empty state: "No memories yet — complete a meetup to create your first one."
- Error state: "Couldn't load memories" with a retry button.

---

### `HomeView` changes

- Adds a fourth tab: **Memories** (`clock.arrow.circlepath` SF symbol) hosting `MeetupMemoriesView`.

---

## Environment Setup

1. Obtain `SUPERMEMORY_API_KEY` from https://console.supermemory.ai.
2. Add to Supabase Edge Function secrets:
   ```bash
   supabase secrets set SUPERMEMORY_API_KEY=<key>
   ```
3. Install the SDK in each function directory:
   ```bash
   cd supabase/functions/store-meetup-memory && npm install supermemory
   cd supabase/functions/search-memories && npm install supermemory
   ```
4. The key is accessed in Edge Functions via `Deno.env.get("SUPERMEMORY_API_KEY")`.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| `storeMemory` network failure | Caught silently, logged. Meetup completion is not blocked. |
| `storeMemory` Supermemory API error | Same as above. |
| `searchMemories` failure | Returns `[]`. UI shows empty state or fallback message. |
| Edge Function cold start timeout | `functions.invoke` has a default timeout; falls through to error path. |

---

## Scope

**In scope:**
- Two Supabase Edge Functions (`store-meetup-memory`, `search-memories`)
- `MemoryService.swift` singleton
- `MeetupMemory` Codable struct
- `MeetupDashboardView` — Complete Meetup button + memory store call
- `CreateMeetupView` — past venue quick-picks
- `MeetupMemoriesView` — new screen with search
- `HomeView` — new Memories tab

**Out of scope:**
- Sharing memories with other participants (only the host's memory is stored)
- Editing or deleting memories from within the app
- AI-generated captions or summaries beyond the structured text format above
- Supabase schema changes or new tables
- Caching memories locally for offline access
