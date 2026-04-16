# Release Checklist

## Prerequisites

1. **Apple Developer ID certificate** installed in Keychain (type: "Developer ID Application")
2. **Notarytool credentials** stored in Keychain:
   ```bash
   xcrun notarytool store-credentials "GooseNeck" \
     --apple-id "your@email.com" \
     --team-id "XXXXXXXXXX" \
     --password "app-specific-password"
   ```
3. **Environment variables** set:
   ```bash
   export DEVELOPMENT_TEAM="XXXXXXXXXX"   # Your 10-char Apple Team ID
   export NOTARY_PROFILE="GooseNeck"       # Keychain profile name from step 2
   ```
4. **create-dmg** installed: `brew install create-dmg`
5. **Sparkle signing key** generated (first time only):
   ```bash
   $(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/generate_keys' -type f | head -1)
   ```

## Build Configuration

- Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
- Verify Release config `POLAR_CHECKOUT_URL` and `POLAR_ORGANIZATION_ID` point to production
- Run `make generate` to regenerate the Xcode project

## One-Command Release

```bash
make release DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM NOTARY_PROFILE=$NOTARY_PROFILE
```

This runs the full pipeline:
1. Archive and export `.app` with Developer ID signing
2. Notarize the app with Apple
3. Staple the notarization ticket to `.app`
4. Create distribution zip from stapled app (for Sparkle)
5. Sparkle-sign the zip (EdDSA signature for appcast)
6. Create DMG with drag-to-Applications UI
7. Notarize the DMG container
8. Staple the DMG

Output artifacts in `build/release/`:
- `GooseNeck.app` — signed, notarized, stapled
- `GooseNeck.zip` — for Sparkle auto-updates
- `GooseNeck.dmg` — for website/GitHub download

## After the Build

1. **Copy the Sparkle signature** printed during step 5
2. **Get the zip file size**: `ls -l build/release/GooseNeck.zip`
3. **Update `docs/appcast.xml`**:
   - Add a new `<item>` block (or update the existing one)
   - Set `sparkle:edSignature` to the signature from step 1
   - Set `length` to the file size from step 2
   - Set `sparkle:version` to `CURRENT_PROJECT_VERSION`
   - Set `sparkle:shortVersionString` to `MARKETING_VERSION`
   - Update the download URL to match the GitHub release tag
4. **Create GitHub Release**:
   - Tag: `v{MARKETING_VERSION}` (e.g., `v1.0.0`)
   - Upload both `GooseNeck.zip` and `GooseNeck.dmg`
5. **Push appcast.xml** to the `gooseneck-updates` repo (auto-deploys to Cloudflare Pages at gooseneck-updates.pages.dev)

## Individual Targets

Run steps individually if needed:

```bash
make archive DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM
make export DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM
make notarize NOTARY_PROFILE=$NOTARY_PROFILE
make staple
make package
make sparkle-sign
make dmg
make notarize-dmg NOTARY_PROFILE=$NOTARY_PROFILE
make staple-dmg
```

## Smoke Checks

- Launch the app and confirm menu bar icon appears (no Dock icon)
- Verify monitoring starts without opening the popover
- Verify onboarding calibration changes live posture state
- Verify a missing accelerometer shows a sensor error
- Verify notification actions perform expected app actions
- Verify license state transitions for active, offline grace, invalid, and deactivated
- Verify VoiceOver reads meaningful labels
- On a separate Mac, download the DMG, install, and confirm Gatekeeper passes
- Trigger Sparkle update check and confirm it finds the new version
