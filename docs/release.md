# Release Checklist

## Build Configuration
- Set the Release `POLAR_CHECKOUT_URL` and `POLAR_ORGANIZATION_ID` values in `project.yml` to the production Polar configuration before shipping.
- Regenerate the Xcode project with `make generate` after changing build settings.
- Confirm the release build uses the production `PolarAPIBaseURL` from `Info.plist`.
- Release builds now fail closed if Polar URLs still point at sandbox hosts.

## Signing and Notarization
- Ensure the Xcode project has a valid signing team and certificate for `PostureDesk`.
- Archive the app with `make archive`.
- Create a notarization zip with `make package`.
- Submit with `make notarize NOTARY_PROFILE=<your-keychain-profile>`.
- Staple the notarization ticket with `make staple`.

## Smoke Checks
- Launch the app without opening the menu bar popover and confirm monitoring starts.
- Verify onboarding calibration changes live posture state.
- Verify a missing accelerometer shows a sensor error instead of a fake connected state.
- Verify notification actions perform the expected app actions.
- Verify license state transitions for active, offline grace, invalid, and deactivated states.
- Verify VoiceOver reads meaningful labels for onboarding, popover actions, settings controls, and the Posture Island action button.
