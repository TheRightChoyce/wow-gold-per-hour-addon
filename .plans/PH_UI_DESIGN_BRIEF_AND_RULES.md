# pH UI Design Brief (Theme A — Alchemical Readout)
**Goal:** A WoW Classic–native “instrument” UI that measures **per hour** metrics.  
**Principles:** Calm, readable, accurate, consistent. No hype. No clutter.

> **Revision note:** Text colors have been darkened for improved readability against dark Classic UI backgrounds.

---

## 1) Visual Style
- Serif headers, darker parchment text, bronze borders
- High contrast for dungeon/raid lighting
- Literal, calm labeling throughout

---

## 2) Design Tokens

### Color Tokens (Classic-safe RGB 0–1)

```lua
-- Text (improved contrast)
PH_TEXT_PRIMARY   = { r=0.92, g=0.89, b=0.80 }
PH_TEXT_MUTED     = { r=0.72, g=0.68, b=0.60 }

-- Accents
PH_ACCENT_GOOD    = { r=0.30, g=0.85, b=0.48 }
PH_ACCENT_NEUTRAL = { r=0.60, g=0.76, b=0.60 }
PH_ACCENT_BAD     = { r=0.85, g=0.38, b=0.32 }

-- Backgrounds
PH_BG_DARK        = { r=0.06, g=0.05, b=0.04 }
PH_BG_PARCHMENT   = { r=0.16, g=0.14, b=0.11 }

-- Borders
PH_BORDER_BRONZE  = { r=0.55, g=0.45, b=0.30 }
PH_DIVIDER_DARK   = { r=0.18, g=0.16, b=0.14 }
```

---

## Typography, Spacing, Components, and Cursor/Claude Rules
Unchanged from the previous version — only color contrast has been adjusted.
