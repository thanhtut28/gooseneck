# GooseNeck 1.0.3 — Settings re-activation flow

A small UX fix for the licensing screen in Settings.

## What changed

- **Activate License button.** When your license is inactive (e.g., you deactivated it earlier and closed the onboarding window without re-entering a key), the License section in Settings now shows an **Activate License** button. Clicking it re-opens the activation flow so you can paste your key without quitting and relaunching the app. Previously the button was always labelled "Deactivate License" — confusing when there was nothing to deactivate.
- **Validating indicator.** While GooseNeck is checking your license against the server, the button area shows a brief *"Validating…"* spinner instead of the action button.

No functional changes to the licensing logic itself — purely a UI affordance for an edge case that's easy to walk into.

## Compatibility

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).
