# Pre-Launch Checklist

Run this checklist **before** executing `make release` (see `docs/release.md` for the actual release pipeline). This document answers *"is the app ready to ship?"* — `release.md` answers *"how do I ship it?"*.

Allow ~45 minutes end-to-end on a clean-ish Mac.

---

## 1. Golden-Path Smoke Test (~15 min)

Reset to a clean state, then walk the full onboarding + first-session flow.

```bash
killall GooseNeck 2>/dev/null || true
rm -rf ~/Library/Application\ Support/GooseNeck/
defaults delete com.gooseneck.app onboardingComplete 2>/dev/null || true
defaults delete com.gooseneck.app onboardingSetupComplete 2>/dev/null || true
```

Then launch the build you intend to ship (`open build/release/GooseNeck.app`) and verify each step:

- [ ] **Onboarding appears** starting at `.welcome`.
- [ ] All onboarding steps advance without error: welcome → privacy/terms → accelerometer detected → lid angle detected → typing intensity bars respond to keystrokes → surface selection → calibrate → island preview → activate (enter production license key) → complete.
- [ ] Menu-bar icon transitions to `.good` after calibration.
- [ ] Sit straight for 2+ minutes — session is created (check History after session ends). Sessions <2 min are intentionally discarded.
- [ ] Lean forward ~15° for 90s — drift alert fires, icon switches to `.drifting`, optional macOS notification appears.
- [ ] Type on the keyboard for 30s — typing intensity bars rise above zero.
- [ ] Click **Pause** from the popover — icon goes `.away`, sensor suspends.
- [ ] Click **Resume** — sensor reconnects within ~2s, monitoring resumes.
- [ ] Close the lid for 30s, reopen — sensor reconnects automatically.
- [ ] Quit the app, relaunch — finalized session appears in **History**.

---

## 2. Audit-Driven Edge Cases

These map 1:1 to the Batches 1–4 production fixes. Each takes 2–5 minutes.

### 2.1 Storage-failure banner (Batch 1A)

```bash
chmod -w ~/Library/Application\ Support/GooseNeck/
```

- [ ] Use the app for ~90s so `updateCurrentSession` fires 3+ times.
- [ ] Dashboard displays the **"History isn't saving"** banner (accent-danger red).
- [ ] Restore permissions: `chmod +w ~/Library/Application\ Support/GooseNeck/`.
- [ ] Banner clears on the next successful save.

### 2.2 Orphan-recovery logging (Batch 1B)

- [ ] Start a session, let it run ≥2 min.
- [ ] `killall -9 GooseNeck` mid-session.
- [ ] Relaunch. Session appears in History with a reasonable `endedAt`.
- [ ] If recovery ever fails, verify it's logged:
  ```bash
  log show --predicate 'subsystem == "com.gooseneck.app" AND category == "storage"' --last 10m
  ```

### 2.3 Catastrophic storage fallback (Batch 1C)

Inspection only — near-impossible to trigger at runtime. Confirm no `try!` remains:

```bash
grep -n "try!" PostureDesk/PostureDeskApp.swift
# expected: no matches
```

### 2.4 Lid-angle baseline (Batch 2A)

- [ ] Calibrate with the lid open (a normal laptop posture).
- [ ] Manually close the lid so the sensor returns `-1` (the app will keep running on external display).
- [ ] Confirm the tilt/drift numbers stay stable — they do **not** spike or swing wildly.
- [ ] Re-open the lid — drift resumes computing from the baseline.

### 2.5 Fatigue calendar-day decay (Batch 2C)

Inspection is sufficient. Optional clock-rollback test is **skippable** (changing system clock can break TLS / notarization checks):

```bash
grep -n "Calendar.current.dateComponents" PostureDesk/Services/FatigueMonitor.swift
# expected: one match on the time-decay line
```

### 2.6 Notification permission denial (Batch 3A + 3C)

- [ ] Fresh install, deny the notification permission when prompted at calibration.
- [ ] Onboarding calibrate step shows the **"Notifications are off"** inline hint.
- [ ] Dashboard shows the red **"Notifications are off in System Settings"** banner.
- [ ] Click **Open Settings** — System Settings opens directly on the Notifications pane for GooseNeck.
- [ ] Grant permission in System Settings → return to app → both banners disappear.

### 2.7 History loading state (Batch 4A)

- [ ] With an existing history of ≥100 sessions (from normal dev use), open the History tab.
- [ ] A `ProgressView` labeled *"Loading history…"* appears briefly before the list renders.

### 2.8 Settings launch-at-login sync (Batch 4B)

- [ ] Open **Settings** → confirm **Launch at Login** toggle state.
- [ ] Toggle it in **System Settings → General → Login Items** externally.
- [ ] Close and reopen the app's Settings view → the toggle reflects the new state.

---

## 3. Release Build Integrity

Run the full production pipeline:

```bash
make release DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM NOTARY_PROFILE=$NOTARY_PROFILE
```

Then verify:

- [ ] **Info.plist points at production endpoints:**
  ```bash
  /usr/libexec/PlistBuddy -c "Print :PolarAPIBaseURL" build/release/GooseNeck.app/Contents/Info.plist
  # expected: https://api.polar.sh/v1/customer-portal/license-keys
  /usr/libexec/PlistBuddy -c "Print :PolarCheckoutURL" build/release/GooseNeck.app/Contents/Info.plist
  # expected: https://api.polar.sh/v1/checkout-links/...
  ```
- [ ] **Code signing is Developer ID, Hardened Runtime enabled:**
  ```bash
  codesign -dv --verbose=4 build/release/GooseNeck.app 2>&1 | grep -E "Authority|flags"
  # expected: Authority=Developer ID Application: ...
  # expected: flags=0x10000(runtime)
  ```
- [ ] **Notarization stapled:**
  ```bash
  spctl --assess --type execute build/release/GooseNeck.app
  # expected: accepted source=Notarized Developer ID
  ```
- [ ] **No sandbox strings leaked into the binary:**
  ```bash
  strings build/release/GooseNeck.app/Contents/MacOS/GooseNeck | grep -i sandbox
  # expected: no matches
  ```
- [ ] **Production license key activates:** launch the stapled `.app`, enter a real production Polar license, confirm activation succeeds.

---

## 4. Performance Targets (Release Build Only)

Measurement conditions: popover **closed**, Dynamic Island **off**, app running ≥2 minutes warm-up.

| Metric | Target | How to measure |
| --- | --- | --- |
| CPU (idle) | < 2% | Activity Monitor → CPU column |
| Energy Impact | < 2 | Activity Monitor → Energy column |
| Memory (steady) | < 50 MB | Activity Monitor → Memory column |
| Leak growth (30 min) | none | Instruments → Leaks (optional) |

If any number misses its target, **defer the launch** and open a follow-up for profile-guided optimization — do not ship.

---

## 5. Profiling-Tooling Cleanup

This session added a local Release-profiling path. Confirm none of it leaks into the shipped binary.

### Safe to keep in the repo

These are build-time tools only; they never run inside the shipped `.app`:

- `Makefile:build-release` — produces a Release-optimized local build with ad-hoc signing.
- `Makefile:run-release` — rebuilds + launches the local build.

### Must NOT appear in `project.yml` Release config

```bash
grep -n "PROFILING" project.yml
# expected: no matches (PROFILING is only a transient xcodebuild arg)

awk '/^[[:space:]]*(Debug|Release):/{cfg=$1} cfg && /sandbox/{print cfg" "NR": "$0}' project.yml
# expected: only "Debug:" lines — never "Release:"
```

### Must NOT appear in committed source

```bash
grep -n "elseif PROFILING" PostureDesk/Services/LicenseManager.swift
# expected: no matches

grep -rn "AllowSandbox\|DisableLicenseGuard\|BypassLicense" PostureDesk/
# expected: no matches
```

If any of these grep commands returns results, **fix before releasing.** The sandbox-URL guard in `LicenseManager.swift:defaultRequiresProductionConfiguration` must remain Debug-only.

---

## 6. Distribution Sanity (Ideally on a Clean Mac)

- [ ] Download the notarized DMG from the intended distribution channel (GitHub Releases / website).
- [ ] Open the DMG, drag GooseNeck.app to Applications, launch — Gatekeeper should accept without the "unidentified developer" prompt.
- [ ] Run through Section 1 (golden path) on this install.
- [ ] Point at a test appcast, trigger **Check for Updates** → confirm Sparkle downloads, verifies signature, and installs the update.

---

## Sign-off

Only proceed to `make release` once every item in Sections 1–5 is checked. Section 6 can be deferred to post-release validation on a test machine if a clean Mac isn't available at release time.
