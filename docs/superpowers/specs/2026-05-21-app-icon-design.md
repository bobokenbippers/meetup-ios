# App Icon — Design Spec

**Date:** 2026-05-21
**Status:** Implemented

---

## Design Direction

Energetic & Modern. Two brunch drinks clinking — a Mimosa champagne flute (left) and a Bloody Mary highball (right) — on a dark background with a coral glow at the base. Directly expresses the "Squad Brunch" name.

---

## Visual System

| Token | Value |
|---|---|
| Background | `#0F0F14` (near-black) |
| Background glow | Radial `#FF6B47` at 22% opacity, centered bottom |
| Clink starburst | `#FF6B47` coral-orange |
| Mimosa fill | Linear gradient `#FFE880` → `#FFB020` → `#E87800` |
| Bloody Mary fill | Linear gradient `#D84020` → `#6A0E08` |
| Glass outline | `rgba(255,255,255,0.62)`, 5.5pt stroke |

---

## Icon Elements

**Left — Mimosa flute** (base at canvas ~31%, tilted +12° toward center)
- Narrow tapered champagne flute shape with stem and base plate
- Orange juice gradient fill; white foam cap with bubble clusters
- 6 scattered bubble circles in the liquid
- Left-side inner highlight for glass depth
- Orange slice garnish on the right rim: peel, flesh, segment spokes, white pith arc

**Right — Bloody Mary highball** (base at canvas ~68%, tilted −12° toward center)
- Straight-sided highball with slight outward taper, base plate
- Deep tomato-red gradient fill
- 3 translucent ice cubes with glow
- Salt rim: 6 white dot circles along top edge
- Celery stalk with gradient green, inner vein highlight, and 3 leaf ellipses
- Lemon wedge on left rim: peel, flesh, white pith arc, segment lines

**Center — Clink starburst** (~x=512, y=242)
- Radial glow orb (coral, 22% opacity, r=42)
- 6 long primary rays (every 60°) + 6 short secondary rays (rotated 30°)
- Coral centre dot with white inner highlight

---

## Generator

`scripts/generate_icon.py` — outputs `1024×1024` PNG via `rsvg-convert`.

```bash
python3 scripts/generate_icon.py
```

Output: `meetup-ios/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png`
