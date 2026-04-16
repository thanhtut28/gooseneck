# Weekly Chart Polish — Hollow Rings + Pulse

## Context

The weekly "daily active time" chart in HistoryView uses Swift Charts with large filled `PointMark` circles (symbolSize 80/120) that dominate the 220pt chart frame. The fat knobs clash with the refined Catmull-Rom curve and area gradient, making the chart feel clunky. This spec refines the data points and supporting elements to match the app's premium dark-mode aesthetic.

## Scope

Single file: `PostureDesk/Views/History/HistoryView.swift`, function `weeklyChart(using:)` (lines 209–308). No new files. No model changes. No design system changes.

## Changes

### 1. Data Point Dots — Hollow Rings

**Current:** `PointMark` with flat filled circles, `symbolSize(80)` / `symbolSize(120)` when selected.

**New:** `PointMark` with custom `.symbol` modifier rendering hollow rings:

- **Unselected:** `symbolSize` ~20. Custom symbol: `Circle().strokeBorder(lineWidth: 1.5)` — dark center (`cardBg` or `clear` fill implied by stroke-only), indigo stroke.
- **Selected:** `symbolSize` ~35. Custom symbol: filled `Circle()` — solid indigo fill.
- **Alert days (alertRate > 2):** Stroke/fill color switches to `DS.Colors.accentWarn`.

Implementation via `PointMark.symbol { }` view builder, branching on `isSelected(day.date)`.

### 2. Pulse Animation on Selected Point

Add a breathing glow ring around the selected data point using a `chartOverlay` with `GeometryProxy`:

- Read the selected point's position via `proxy.position(forX:)` to place an overlay circle.
- Outer ring: `Circle().stroke(accentInfo.opacity(0.15), lineWidth: 1.5)`, 14pt diameter.
- Animation: `scaleEffect` cycling `1.0 → 1.6 → 1.0` with `.easeInOut(duration: 2.5).repeatForever(autoreverses: true)`.
- Opacity fades in sync: `0.15 → 0.03 → 0.15`.
- Driven by a `@State private var pulseActive = false`, toggled `.onAppear`.

### 3. Line Weight

**Current:** `StrokeStyle(lineWidth: 3, ...)`
**New:** `StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)`

### 4. Area Gradient

**Current:**
```swift
[DS.Colors.accentInfo.opacity(0.4),
 DS.Colors.accentInfo.opacity(0.0)]
```

**New — 3-stop smoother fade:**
```swift
[DS.Colors.accentInfo.opacity(0.3),
 DS.Colors.accentInfo.opacity(0.12),
 DS.Colors.accentInfo.opacity(0.0)]
```

### 5. Tooltip Card

**Current border:** `textMuted.opacity(0.2)`, `lineWidth: 1`
**New border:** `textMuted.opacity(0.15)`, `lineWidth: 1`

**Add shadow:** `.shadow(color: .black.opacity(0.2), radius: 8, y: 4)` on the tooltip background.

## Implementation Notes

- Swift Charts `PointMark.symbol { }` accepts a SwiftUI view builder — use this for the hollow ring vs filled circle branching.
- The pulse overlay uses `chartOverlay(content:)` with `GeometryProxy` to convert data coordinates to view coordinates. Only render when `selectedDate != nil`.
- The `proxy.position(forX: selectedDate)` call returns the x position; y position comes from the corresponding `DailySummary.activeMinutes` value via `proxy.position(forY: minutes)`.
- Keep the existing `chartXSelection(value: $selectedDate)` interaction — no change to selection mechanics.
- The `RuleMark` dashed selection line stays as-is.

## What Does NOT Change

- Chart height (220pt), padding (24pt), dsCard wrapper
- X-axis / Y-axis label styling
- Catmull-Rom interpolation method
- RuleMark selection indicator
- Tooltip content (date, duration, alert rate)
- `chartXSelection` interaction binding
- Animation on `selectedDate` (easeOut 0.2s)

## Verification

1. `make build` — compiles without errors
2. `make run` — open History tab, verify:
   - Unselected days show small hollow indigo rings
   - Alert days (alertRate > 2) show amber rings
   - Clicking a day: ring fills solid, breathing pulse appears, tooltip shows with shadow
   - Line is visibly thinner than before
   - Area gradient fades more smoothly (no harsh cutoff)
   - Tooltip border is softer, has subtle drop shadow
3. Test with 0 sessions (empty state) — chart should still render cleanly
4. Test with 1 session day — single dot renders as hollow ring
