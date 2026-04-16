.PHONY: generate build clean run archive export package notarize staple sparkle-sign dmg notarize-dmg staple-dmg release

generate:
	xcodegen generate

build: generate
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck -configuration Debug build SYMROOT=$(CURDIR)/build

clean:
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck clean 2>/dev/null || true
	rm -rf build

run: build
	open build/Debug/GooseNeck.app

ARCHIVE_PATH ?= $(CURDIR)/build/GooseNeck.xcarchive
EXPORT_PATH  ?= $(CURDIR)/build/release
APP_PATH     ?= $(EXPORT_PATH)/GooseNeck.app
ZIP_PATH     ?= $(EXPORT_PATH)/GooseNeck.zip
DMG_PATH     ?= $(EXPORT_PATH)/GooseNeck.dmg
NOTARY_PROFILE ?=

archive: generate
	@test -n "$(DEVELOPMENT_TEAM)" || (echo "Error: DEVELOPMENT_TEAM env var is required for release builds" >&2 && exit 1)
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck -configuration Release \
		archive -archivePath $(ARCHIVE_PATH) \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"

export: archive
	rm -rf $(EXPORT_PATH)
	mkdir -p $(EXPORT_PATH)
	cp -R "$(ARCHIVE_PATH)/Products/Applications/GooseNeck.app" "$(APP_PATH)"

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
