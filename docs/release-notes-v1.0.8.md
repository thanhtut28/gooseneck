# GooseNeck 1.0.8 — onboarding "Get Started" finally clear

The "GooseNeck quit when I clicked Get Started" perception has been a persistent paper-cut. v1.0.7 attempted to auto-open the dashboard via `openWindow(id:)`, but that's a no-op when the calling SwiftUI view is hosted in an `NSHostingView` outside any SwiftUI scene (which is how the onboarding window is set up). v1.0.8 takes a more reliable approach.

## What's fixed

**Stronger menu-bar coach mark.** The final onboarding screen now shows a prominent up-arrow with "GooseNeck lives up there" pointing toward the menu bar, plus a longer explanation that the app keeps running in the background. The button label changed from "Get Started" (which sounded like it would do something) to "Done" (which sets the right expectation about closing this window).

**Dock icon stays visible after onboarding.** The app no longer drops to menu-bar-only mode immediately when you finish setup. The Dock icon stays as a fallback "the app is running" signal until you open and then close the dashboard, at which point the app naturally transitions to menu-bar-only.

**Clicking the Dock icon opens the dashboard.** New `applicationShouldHandleReopen` handler — if the app is running but no windows are visible, clicking the Dock icon reliably brings up the dashboard.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
