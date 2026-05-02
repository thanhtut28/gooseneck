# GooseNeck 1.0.14 — fixes unreadable popover text in dark mode

A small visual fix.

## What changed

Two pieces of secondary status text in the menu bar popover (and floating island pill, for "Away") were rendered in our `textMuted` color, which on dark mode (`#52525B` against `#16161A` card background) was nearly invisible. Light mode was also too faint for primary 12–16pt status text.

- **"Away"** status, when you step away from the keyboard.
- **"Idle"** typing-intensity value, when you're not actively typing.

Both now use `textSecondary` — the same contrast level as the "Current Posture" / "Session" labels around them — so they're readable in both light and dark appearances.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
