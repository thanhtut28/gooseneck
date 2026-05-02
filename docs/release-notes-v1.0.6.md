# GooseNeck 1.0.6 — Activate License button (really fixed this time)

v1.0.5 attempted to fix the Activate License button via Swift concurrency adjustments; that wasn't the root cause. v1.0.6 defers the window-opening past the current SwiftUI runloop tick using `DispatchQueue.main.async`, which is the actual canonical pattern for window mutation triggered from a SwiftUI button.

If the cast to AppDelegate ever fails (it shouldn't), a visible alert now appears instead of silently swallowing the click.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
