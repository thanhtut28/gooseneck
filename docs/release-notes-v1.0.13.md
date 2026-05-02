# GooseNeck 1.0.13 — fixes leftover Dock icon after onboarding

A one-line follow-up to v1.0.12.

## What changed

After completing onboarding (clicking Done), the app was leaving its Dock icon visible instead of returning to menu-bar-agent state. The activation policy is supposed to flip back to `.accessory` on completion — that line was lost in the v1.0.11 closure rewrite and v1.0.12 didn't catch it.

This release restores `NSApp.setActivationPolicy(.accessory)` to the onboarding completion path. Click Done → window closes → Dock icon disappears within a second → menu bar icon stays.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
