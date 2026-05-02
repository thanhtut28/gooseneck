# GooseNeck 1.0.10 — fix Done crash (real this time)

v1.0.9 was supposed to fix the crash from v1.0.8 but introduced (or carried over) a different one. The crash trace shows the actual cause: an AppKit window-close animation use-after-free.

## What was crashing

When you clicked Done on the final onboarding screen, AppKit started its default window-close transform animation. The window's content was an `NSHostingView` wrapping the SwiftUI `OnboardingView`. As SwiftUI's view tree was being torn down on the same runloop tick, the AppKit close animation's deallocation hit a freed reference, segfaulting in `objc_release` inside the autorelease pool drain.

## What v1.0.10 changes

Three layered fixes (defense in depth):

1. **Window animation disabled** — the onboarding NSWindow is now created with `.animationBehavior = .none`, so the buggy transform animation never runs.
2. **Close deferred** — `window.close()` now happens on the next runloop tick (`DispatchQueue.main.async`) instead of synchronously inside the SwiftUI binding setter. This separates SwiftUI tear-down from AppKit dealloc.
3. **Symbol-effect removed** — the up-arrow on the completion screen no longer uses `.symbolEffect(.bounce)`. Static arrow only. The animation was a contributing factor.

After these, clicking Done cleanly closes the onboarding window and leaves the Dock icon visible.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
