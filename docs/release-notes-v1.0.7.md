# GooseNeck 1.0.7 — Activate License button + onboarding "Get Started" UX

Two related fixes that close out the activation/onboarding paper-cuts.

## What's fixed

**Activate License button (Settings).** Clicking it from Settings → License & About now reliably opens the activation flow. The previous attempt in v1.0.5/v1.0.6 hit an `NSApp.delegate` cast that returned nil from a SwiftUI Button context. Switching to a static `AppDelegate.shared` reference sidesteps the SwiftUI delegate-wrapper quirk entirely. The fallback alert that appeared in v1.0.6 should never fire now.

**Onboarding "Get Started" no longer appears to quit the app.** Previously, clicking Get Started on the final onboarding screen closed the onboarding window and immediately dropped the app to menu-bar-only mode — no Dock icon, no visible window. Brand-new users had no learned association with the menu bar icon and assumed the app crashed. Now the dashboard opens automatically right after Get Started, giving an unambiguous "the app is running" signal. The app transitions to menu-bar-only naturally when you close the dashboard.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
