# GooseNeck 1.0.16 — 7-day free trial

Introduces a free trial, with a local cutoff so it ends on time even if the app never restarts.

## What's new

**7-day free trial.** The onboarding screen now offers a "Start 7-day Free Trial" button alongside the existing Buy option. Tap it, complete a $0 checkout on Polar with your email, and you get a trial license key that activates the full app for a week — no card required.

The trial is gated to **one per Mac**. Once a trial has been used on this Mac (tracked via a Keychain marker and the hardware ID), the trial CTA disappears and only the Buy option remains. This closes the obvious "new email = new trial" loop without needing any backend infrastructure.

While the trial is active, the menu bar popover shows a thin banner with days remaining and a Subscribe link; the urgency color shifts when ≤1 day is left. When the trial ends, the popover replaces its content with a lock card and a prominent Subscribe button. Settings → License gains matching Subscribe CTAs.

**Hard local cutoff.** MacBooks frequently sleep rather than restart, so the trial-ended state is now driven by a local timer in addition to the Polar status check. The app transitions to the trial-expired UI the moment your trial deadline passes, even if you've kept the app running continuously since activation.

## Under the hood

- Trial detection is `expires_at`-based — any license key Polar returns with an expiry is treated as a trial. Paid keys (no expiry) behave exactly as before.
- The Polar activation `label` now includes a short hash of `IOPlatformUUID` (e.g. `"Than's MBP · 7a3f2b1c"`), so future server-side dedupe can group activations by Mac without exposing the raw hardware identifier.
- Post-fact gate: if you try to activate a trial key on a Mac that already burned its trial, the activation is immediately deactivated against Polar so the slot isn't wasted, and the app surfaces "Free trial already used on this Mac."

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
