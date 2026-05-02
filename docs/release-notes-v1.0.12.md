# GooseNeck 1.0.12 — fixes the onboarding "Done" crash for real

The onboarding flow has been crashing on the Done click since 1.0.6. Five previous releases (1.0.7 → 1.0.11) attempted increasingly elaborate fixes — none of them addressed the actual bug.

v1.0.12 is a one-line fix to a classic AppKit lifecycle pitfall.

## What was actually wrong

`NSWindow.isReleasedWhenClosed` defaults to `true` on programmatically-created windows. The onboarding window stored a strong reference to itself on the AppDelegate, so every Done click did:

1. `close()` → AppKit calls `release` on the window (count drops once)
2. `onboardingWindow = nil` → ARC calls `release` again (count drops twice)
3. Object dealloc'd, but AppKit still has internal references in the autorelease pool
4. Next runloop tick → autorelease pool drain → `objc_release` SIGSEGV

This is documented in Apple's NSWindow.h header — when you keep a Swift reference to a programmatically-created window, you must opt out of AppKit's auto-release-on-close. We never did.

The earlier "fixes" all chased downstream symptoms: animation behavior, deferred close on the next runloop, `NSHostingView` → `NSHostingController`, `@Binding` → closure callback. None of those were the actual cause; the over-release was happening regardless.

## The fix

```swift
let window = NSWindow(...)
window.isReleasedWhenClosed = false  // ← v1.0.12
```

Plus dropping the SwiftUI hosting controller before `close()` so the view tree releases cleanly before AppKit tears the window down.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
