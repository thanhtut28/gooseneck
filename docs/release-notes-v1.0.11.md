# GooseNeck 1.0.11 — onboarding window architecture rewrite

The onboarding flow has been crashing on the Done click since 1.0.6. Each previous attempted fix targeted a different symptom of the same underlying issue: SwiftUI `@Binding` lifecycle racing AppKit window dealloc inside an `NSHostingView` on macOS 26.

v1.0.11 replaces the architecture, not just patches the symptoms.

## What changed

- **`NSHostingView` → `NSHostingController`**. NSHostingController is the canonical AppKit container for SwiftUI views used as a window's contentViewController. NSHostingView is intended for embedding SwiftUI inside an existing AppKit view hierarchy and has subtle lifecycle issues when used as a top-level window content on recent macOS versions.
- **`@Binding<Bool>` completion → closure callback**. The previous "isComplete" binding had SwiftUI re-evaluating the view tree at the same time AppKit was tearing down the window, leading to autorelease-pool over-release crashes (`objc_release` SIGSEGV inside `NSAutoreleasePool drain`). A plain callback removes that lifecycle entanglement entirely.
- All v1.0.10 fixes retained: window animations disabled, close deferred to next runloop, no symbol-effect on the up-arrow.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
