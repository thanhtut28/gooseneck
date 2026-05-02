.PHONY: generate build build-release clean run run-release archive export package notarize staple sparkle-sign dmg notarize-dmg staple-dmg release

generate:
	xcodegen generate

build: generate
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck -configuration Debug build SYMROOT=$(CURDIR)/build

# Release-optimized build for local profiling (ad-hoc signed, no notarization).
# Use this to measure realistic CPU / energy numbers — Debug builds are 5–10× slower.
# - Hardened Runtime is disabled so the ad-hoc signed app can load Sparkle.framework.
# - Polar endpoints are pinned to sandbox so a dev license key still authenticates
#   (production endpoints are used by `make release`).
build-release: generate
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck -configuration Release build SYMROOT=$(CURDIR)/build \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
		POLAR_API_BASE_URL="https://sandbox-api.polar.sh/v1/customer-portal/license-keys" \
		POLAR_CHECKOUT_URL="https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_DOGu45YJUcHzeFxGZw5EqT0L9gN3L9Qm2dTQn2Z4xHn/redirect"

clean:
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck clean 2>/dev/null || true
	rm -rf build

run: build
	open build/Debug/GooseNeck.app

# Run the Release-optimized build. Kill any running copy first so the menu bar agent is fresh.
run-release: build-release
	-killall GooseNeck 2>/dev/null || true
	open build/Release/GooseNeck.app

ARCHIVE_PATH ?= $(CURDIR)/build/GooseNeck.xcarchive
EXPORT_PATH  ?= $(CURDIR)/build/release
APP_PATH     ?= $(EXPORT_PATH)/GooseNeck.app
ZIP_PATH     ?= $(EXPORT_PATH)/GooseNeck.zip
DMG_PATH     ?= $(EXPORT_PATH)/GooseNeck.dmg
EXPORT_OPTIONS_PLIST := $(EXPORT_PATH)/ExportOptions.plist
NOTARY_PROFILE ?=

archive: generate
	@test -n "$(DEVELOPMENT_TEAM)" || (echo "Error: DEVELOPMENT_TEAM env var is required for release builds" >&2 && exit 1)
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck -configuration Release \
		archive -archivePath $(ARCHIVE_PATH) \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"

# Canonical Developer ID export: re-signs the archive's .app with the
# Developer ID Application identity, validates entitlements, and embeds
# the signing certificate. Generates a fresh ExportOptions.plist each
# time so DEVELOPMENT_TEAM stays out of the repo.
export: archive
	@test -n "$(DEVELOPMENT_TEAM)" || (echo "Error: DEVELOPMENT_TEAM env var is required" >&2 && exit 1)
	rm -rf $(EXPORT_PATH)
	mkdir -p $(EXPORT_PATH)
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n  <key>method</key><string>developer-id</string>\n  <key>signingStyle</key><string>automatic</string>\n  <key>teamID</key><string>$(DEVELOPMENT_TEAM)</string>\n</dict>\n</plist>\n' > "$(EXPORT_OPTIONS_PLIST)"
	xcodebuild -exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath "$(EXPORT_PATH)" \
		-exportOptionsPlist "$(EXPORT_OPTIONS_PLIST)"

notarize:
	@test -n "$(NOTARY_PROFILE)" || (echo "Error: NOTARY_PROFILE is required" >&2 && exit 1)
	ditto -c -k --keepParent "$(APP_PATH)" "$(EXPORT_PATH)/GooseNeck-notarize.zip"
	xcrun notarytool submit "$(EXPORT_PATH)/GooseNeck-notarize.zip" \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	rm -f "$(EXPORT_PATH)/GooseNeck-notarize.zip"

staple:
	xcrun stapler staple "$(APP_PATH)"

package:
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_PATH)"

sparkle-sign:
	@test -f "$(ZIP_PATH)" || (echo "Error: $(ZIP_PATH) not found. Run 'make package' first." >&2 && exit 1)
	$$(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1) "$(ZIP_PATH)"

dmg:
	@command -v create-dmg >/dev/null 2>&1 || (echo "Error: create-dmg not found. Install with: brew install create-dmg" >&2 && exit 1)
	rm -f "$(DMG_PATH)"
	rm -rf "$(EXPORT_PATH)/dmg-staging"
	mkdir -p "$(EXPORT_PATH)/dmg-staging"
	cp -R "$(APP_PATH)" "$(EXPORT_PATH)/dmg-staging/"
	create-dmg \
		--volname "GooseNeck" \
		--volicon "$(APP_PATH)/Contents/Resources/AppIcon.icns" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 160 \
		--icon "GooseNeck.app" 180 170 \
		--hide-extension "GooseNeck.app" \
		--app-drop-link 480 170 \
		--no-internet-enable \
		"$(DMG_PATH)" \
		"$(EXPORT_PATH)/dmg-staging/"
	rm -rf "$(EXPORT_PATH)/dmg-staging"

notarize-dmg:
	@test -n "$(NOTARY_PROFILE)" || (echo "Error: NOTARY_PROFILE is required" >&2 && exit 1)
	xcrun notarytool submit "$(DMG_PATH)" \
		--keychain-profile "$(NOTARY_PROFILE)" --wait

staple-dmg:
	xcrun stapler staple "$(DMG_PATH)"

release:
	@test -n "$(DEVELOPMENT_TEAM)" || (echo "Error: DEVELOPMENT_TEAM env var is required" >&2 && exit 1)
	@test -n "$(NOTARY_PROFILE)" || (echo "Error: NOTARY_PROFILE env var is required" >&2 && exit 1)
	@echo "==> Step 1/8: Archiving and exporting..."
	$(MAKE) export
	@echo "==> Step 2/8: Notarizing app..."
	$(MAKE) notarize
	@echo "==> Step 3/8: Stapling app..."
	$(MAKE) staple
	@echo "==> Step 4/8: Creating distribution zip..."
	$(MAKE) package
	@echo "==> Step 5/8: Sparkle signing zip..."
	$(MAKE) sparkle-sign
	@echo "==> Step 6/8: Creating DMG..."
	$(MAKE) dmg
	@echo "==> Step 7/8: Notarizing DMG..."
	$(MAKE) notarize-dmg
	@echo "==> Step 8/8: Stapling DMG..."
	$(MAKE) staple-dmg
	@echo ""
	@echo "Release complete!"
	@echo "  App: $(APP_PATH)"
	@echo "  Zip: $(ZIP_PATH) (for Sparkle updates)"
	@echo "  DMG: $(DMG_PATH) (for website/GitHub)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Update docs/appcast.xml with the Sparkle signature printed above"
	@echo "  2. Upload GooseNeck.zip and GooseNeck.dmg to GitHub Releases"
	@echo "  3. Push appcast.xml to gooseneck-updates repo"
