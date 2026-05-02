# GooseNeck 1.0.4 — auto-updates now actually work

A critical fix for the in-app updater.

## What's fixed

**Sparkle auto-updates.** In v1.0.0 through v1.0.3, the updater was created but never started — meaning the "Check for Updates" button was permanently disabled, automatic checks never ran, and the auto-update toggles in Settings did nothing. After installing v1.0.4 once manually, auto-updates work normally for every release after this.

**Settings re-activation flow** (carried over from v1.0.3 — most users never received that release because of the auto-update bug above). The License section in Settings now shows an **Activate License** button when your license is inactive, instead of always showing "Deactivate License".

## Important — one-time manual install

Because of the auto-update bug, **v1.0.0–v1.0.3 cannot pull v1.0.4 via Sparkle**. You'll need to download v1.0.4 manually from this Releases page once. After that, v1.0.5 and every release after will install via the in-app updater the way they should have been all along.

If you bought a license earlier, your license key still works — just enter it again after installing v1.0.4 if Settings prompts you.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
