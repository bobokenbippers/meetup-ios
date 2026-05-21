# UI Redesign — Design Spec

**Date:** 2026-05-20  
**Status:** Ready for implementation  
**Mockups:** `.superpowers/brainstorm/54408-1779332024/content/`

---

## Design Direction

Native iOS 26 feel — glass effects, SF Pro, system dark background — but pushed with energy: coral accent, category color-coded cards, expressive empty states. Not flat or generic; not over-designed.

---

## Visual System

| Token | Value | Usage |
|---|---|---|
| Background | `Color(.systemBackground)` dark | All screens — respects Pure Black / OLED |
| Accent | `#FF6B47` (warm coral-orange) | CTAs, + button, active tab, highlights |
| Glass | `.glassEffect()` / `GlassEffectContainer` | Tab bar, bottom sheets, destination card |
| Typography | SF Pro (system font) | All text — Dynamic Type scaling automatic |
| Corner radius — cards | 18pt | Meetup row cards |
| Corner radius — sheet | 22pt top corners | Bottom sheet on dashboard |
| SF Symbols | `.hierarchical` or `.palette` rendering | All icons — adds depth vs flat gray |

**Category accent colors** (used as card gradients):

| Category | Gradient |
|---|---|
| Dinner / Food | `#C94010` → `#8C2508` |
| Drinks | `#5C3FA0` → `#3D2470` |
| Coffee | `#176035` → `#0C3D20` |
| Hangout / Other | `rgba(255,255,255,0.05)` + border |

---

## Screen 1 — Meetups List (Home)

### Empty state
- Large title: **"Meetups"** (32pt, weight 800, no greeting line)
- Coral + button top-right (34pt circle, `#FF6B47`, shadow)
- Centered empty state:
  - 72×72pt rounded rectangle icon (`#FF6B47` at 12% opacity, 1.5pt border at 25% opacity), 24pt corner radius
  - 📍 emoji inside, ✨ badge top-right corner
  - Radial glow behind icon (`#FF6B47` at 12%, transparent at 70%)
  - Heading: "No meetups yet" (18pt, bold)
  - Body: "Gather your crew and plan something fun." (12pt, 45% white)
  - CTA button: "Plan a Meetup" — coral fill, 14pt bold, 14pt corner radius, shadow

### Populated state
Same header (title + + button). List below with compact rows.

**Section labels:** 10pt, 60% uppercase, no background block — just the text with 4pt padding above. Groups: Invited → Active → Past.

**Meetup row card:**
```
[emoji] [name]              [time]
        [destination]       [status pill]
```
- Border radius: 18pt
- Padding: 14pt vertical, 16pt horizontal
- Invited cards: `rgba(255,255,255,0.05)` + 1pt border at 8% white
- Active cards: category gradient background
- Past cards: same as invited at 50% opacity
- Row gap: 10pt between cards, 4pt section gap
- Emoji: 22pt, left-aligned
- Name: 14pt bold, truncated
- Destination: 11pt, 50% white, truncated
- Time: 10pt, 50% white, right-aligned
- Status pill: 9pt bold, 3pt×8pt padding, 20pt radius
  - Invited: `#FFD600` on 20% yellow background
  - Live: `#2ED573` on 20% green background
  - Late: `#FF4B4B` on 20% red background

### Tab bar
Glass effect (`rgba(22,22,24,0.88)` + `backdrop-filter: blur(24px)`), 1pt top border at 6% white. 3 tabs: Meetups, People, Settings.

---

## Screen 2 — Meetup Dashboard

### Header (above map)
- "Good evening, [Name] 👋" — 12pt, 50% white
- Meetup name as large title — 24pt, weight 800
- "You're meeting N people" — 12pt, 40% white

### Destination card
Glass card: `rgba(30,30,34,0.92)` + blur, 1pt border at 8% white, 14pt radius, 14px side margin.  
Left: 32×32pt coral icon tile (10pt radius) + meetup name (13pt bold) + address (10pt, 40% white).  
Right: time (13pt bold) + countdown in coral (10pt, `#FF6B47`).

### Map
Full-bleed, no horizontal insets, no border, no corner radius clipping. Fills from below the destination card to the top of the bottom sheet.

**Participant pins:** Avatar circle (34pt, 2.5pt white border) + floating callout bubble beside it.  
Callout: `rgba(20,20,24,0.9)` + blur + 1pt border, 10pt radius. Shows name (10pt bold) + ETA colored text.

**ETA colors on map:**
- On time: `#2ED573`
- Late: `#FF4B4B`
- Arrived: 50% white + "✓ Here"

**You pin:** Blue pulsing dot (`#1E90FF`) with outer glow ring + "You" label below.

**Route lines:** Dashed SVG lines from each participant to destination. Color matches participant accent, 50% opacity.

**Overlaid controls:**
- Bottom-left: glass pill "📶 Live traffic ▾"
- Bottom-right: glass circle compass icon

### Bottom sheet
`border-top-left-radius: 22pt`, `border-top-right-radius: 22pt`. Glass background.  
Drag handle (32×3pt, 18% white) at top.  
"Everyone" label (13pt bold).  
Participant rows: avatar (30pt) + name + status detail + ETA (right-aligned, colored) + estimated arrival time (9pt, 30% white).

---

## Screen 3 — People Tab

- Same header treatment: "People" large title + coral + button
- Search bar: `rgba(255,255,255,0.07)` fill, 12pt radius, 🔍 icon + placeholder
- **Friends section:** Glass cards (`rgba(255,255,255,0.05)` + 1pt border, 14pt radius)
  - 38pt avatar circle + name (13pt bold) + context line ("3 meetups together") + badge pill (right)
  - Badge variants: "Crew" (coral tint), "New" (yellow tint), mutual count (green tint)
- **From Meetups section:** Same card style at 60% opacity, coral "+ Add" text on the right

---

## Files to Modify

| File | Change |
|---|---|
| `meetup-ios/Views/MeetupsListView.swift` | Empty state redesign + compact row cards |
| `meetup-ios/Views/MeetupDashboardView.swift` | Full-bleed map, header, destination card, participant pins, glass sheet |
| `meetup-ios/Views/HomeView.swift` | Tab bar glass styling |
| `meetup-ios/Views/PeopleListView.swift` | Friend cards, search bar, badge pills |

No new files needed — all changes are in existing views.

---

## Notes

- The app already uses `.glass` / `.glassProminent` button styles and `GlassEffectContainer` — extend consistently.
- Category colors are hardcoded per category string for now; can be a `switch` on `meetup.category`.
- Participant photo avatars are initials-only for now (no profile photo upload yet).
- Dashboard map uses `Map` content builder (already in `MeetupDashboardView`) — participant pins become custom `MapAnnotation` views matching the new pin style.
