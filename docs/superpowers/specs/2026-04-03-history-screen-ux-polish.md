# History Screen UX Polish — Typography & Visual Hierarchy

## Context

The history screen's visual hierarchy is unpolished. Session cards are cramped (8pt vertical padding), duration — the most important metric — is buried as 11pt muted secondary text, stat labels at 9pt are below macOS comfortable reading size, and date group labels (12pt) are oddly larger than section headers (11pt), creating an inverted hierarchy. This spec addresses all typography and spacing issues across the entire history screen.

## Design Direction

**Refined Compact** — keep cards slim and scannable, but fix the hierarchy so the eye lands on the right information. Duration becomes the hero element in each session row; all text meets the macOS 10pt minimum comfortable reading floor.

## Changes

### 1. Design System Token Updates

These affect the entire app (history, bento cards, chart axes, island widgets), which is intentional — the readability floor should be universal.

**File: `PostureDesk/Views/DesignSystem.swift`**

| Token | Before | After |
|-------|--------|-------|
| `DS.Font.label()` | 11pt medium | **12pt semibold** |
| `DS.Font.caption()` | 10pt regular | **11pt regular** |

Add a new token for session row duration:

```swift
static func rowTitle() -> Font {
    .system(size: 16, weight: .semibold, design: .rounded)
}
```

### 2. Section Headers

All section headers (`"this week"`, `"daily active time"`, `"recent sessions"`) already use `DS.Font.label()`, so they automatically pick up the 12pt semibold change. Additionally, update their color from `textMuted` to `textSecondary` for slightly more prominence.

**File: `PostureDesk/Views/History/HistoryView.swift`**

| Location | Before | After |
|----------|--------|-------|
| "this week" label color | `textMuted` | `textSecondary` |
| "daily active time" label color | `textMuted` | `textSecondary` |
| "recent sessions" label color | `textMuted` | `textSecondary` |

### 3. Date Group Labels (Inverted Hierarchy Fix)

Date group labels ("Today", "Yesterday", etc.) were 12pt semibold — larger than section headers. Demote them to sit below the new 12pt semibold section headers.

**File: `PostureDesk/Views/History/HistoryView.swift`**

| Element | Before | After |
|---------|--------|-------|
| Date group label font | `12pt semibold` | **11pt medium** |
| Date group label color | `textSecondary` | `textSecondary` (unchanged) |

### 4. Session Row Redesign

The biggest change. Duration becomes the primary visual anchor; datetime is demoted to supporting context.

**File: `PostureDesk/Views/History/SessionRow.swift`**

| Element | Before | After |
|---------|--------|-------|
| **Primary text** | Full datetime at 13pt medium | **Duration** at `DS.Font.rowTitle()` (16pt semibold), -0.3pt tracking |
| **Secondary text** | "1h 30m · DESK" at 11pt medium/muted | **"2:30 PM · Desk"** at 11pt medium/muted (time-only `.shortened`, title-cased surface) |
| **Stat values** | 13pt semibold | **14pt semibold** |
| **Stat labels** | 9pt regular / textMuted | **10pt regular / textSecondary**, +0.5pt tracking |
| **Stat label spacing** | 1pt | **2pt** (VStack spacing between value and label) |
| **Stat column gap** | 10pt (HStack spacing) | **16pt** |
| **Card padding** | 8pt vertical, 12pt horizontal | **10pt vertical, 14pt horizontal** |
| **Card corner radius** | 10pt | **12pt** |
| **Card spacing** (HStack) | 12pt | **14pt** |
| **List spacing** (LazyVStack) | 10pt | **8pt** |

The secondary text format changes from showing duration (moved to primary) to showing time and surface: `session.startedAt.formatted(date: .omitted, time: .shortened)` + `session.surface.label` (title case, not uppercased).

### 5. Featured Card Label

**File: `PostureDesk/Views/History/HistoryView.swift`**

| Element | Before | After |
|---------|--------|-------|
| "total active" label | `DS.Font.caption()` / textMuted | `DS.Font.caption()` / **textSecondary** |

The font size change is handled by the global `caption()` token update (10pt → 11pt).

### 6. Bento Card Labels

**File: `PostureDesk/Views/History/HistoryView.swift`**

| Element | Before | After |
|---------|--------|-------|
| Bento card labels | `DS.Font.caption()` / textMuted | `DS.Font.caption()` / **textSecondary** |

Again, the size bump comes from the global token change.

## Files to Modify

1. **`PostureDesk/Views/DesignSystem.swift`** — update `label()`, `caption()`, add `rowTitle()`
2. **`PostureDesk/Views/History/SessionRow.swift`** — full row redesign
3. **`PostureDesk/Views/History/HistoryView.swift`** — section header colors, date group label fix, featured/bento label colors

## Verification

1. `make build` — confirm no compilation errors
2. `make run` — launch the app and navigate to History tab
3. Visually verify:
   - Session rows show duration as the large primary text
   - Time and surface appear as secondary text below duration
   - Section headers ("this week", etc.) are visually larger than date group labels ("Today")
   - All text is readable (no sub-10pt text anywhere on screen)
   - Bento card labels and chart axis labels picked up the global token changes
   - Stats in session rows have clear separation and readable labels
4. Check other screens that use `DS.Font.label()` and `DS.Font.caption()` still look correct (island view, settings)
