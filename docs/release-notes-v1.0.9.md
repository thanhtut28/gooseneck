# GooseNeck 1.0.9 — fix Get Started crash

v1.0.8 had a regression: clicking **Done** on the final onboarding screen crashed the app (`SIGSEGV` / `EXC_BAD_ACCESS`). Root cause was an `openWindow(id: "dashboard")` call from inside the onboarding view, which is hosted in an `NSHostingView` outside any SwiftUI scene — calling SwiftUI's scene API in that context corrupts internal state and segfaults.

The call was a leftover best-effort attempt to auto-open the dashboard after onboarding. v1.0.9 removes it. The Dock icon stays visible after onboarding (as it did in v1.0.8) and `applicationShouldHandleReopen` continues to bring up the dashboard when you click the Dock icon, so the user-facing path is unchanged — just no crash.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
