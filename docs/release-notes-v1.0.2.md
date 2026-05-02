# GooseNeck 1.0.2 — production licensing live

This release wires the app to production Polar — license activation now works for real customers buying through https://gooseneck.app.

## What's new

- **Production licensing.** Activation requests now hit production Polar (`api.polar.sh`) with the GooseNeck organization. The 1.0.0 and 1.0.1 builds pointed at Polar's sandbox, so activation would fail; this release fixes that.
- **Buy Key button**: clicking "Buy Key" or "Get Activation Key" on the website now goes to the live `GooseNeck License` checkout — $14.99 one-time, lifetime license, 3 device activations.

## For existing 1.0.0 / 1.0.1 users

Sparkle will pick up this update automatically. If you'd already entered a license key under one of the earlier sandbox builds, that key will be re-validated against production on next launch — sandbox keys won't work, but if you bought through the production checkout you'll be activated normally.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
