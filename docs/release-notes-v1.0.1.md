# GooseNeck 1.0.1 — refinements

A small follow-up to the 1.0.0 launch, with two real-world UX fixes and an infrastructure cleanup.

## Refinements

- **More accurate typing intensity.** The intensity bar now registers only when keys are actually being pressed. Chassis vibration from fans ramping up, trackpad clicks, music coupling through the speakers, or other environmental sources no longer reads as typing — the metric only counts seconds where macOS reports a real keyDown event in the prior 5 seconds.
- **Cleaner idle state.** When you stop typing, the typing card on the dashboard and in the menu bar popover now shows "idle" in muted grey, instead of a misleading "0% normal" green badge that suggested you were typing perfectly while you actually weren't typing at all.

## Internals

- Auto-update channel moved to `updates.gooseneck.app` (was `gooseneck-updates.pages.dev`). Existing 1.0.0 installs continue to receive updates seamlessly via the previous host, which now serves the same content.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
