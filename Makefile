.PHONY: generate build clean run archive package notarize staple

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
EXPORT_PATH ?= $(CURDIR)/build/release
APP_PATH ?= $(EXPORT_PATH)/GooseNeck.app
ZIP_PATH ?= $(EXPORT_PATH)/GooseNeck.zip
NOTARY_PROFILE ?=

archive: generate
	xcodebuild -project GooseNeck.xcodeproj -scheme GooseNeck -configuration Release archive -archivePath $(ARCHIVE_PATH)

package: archive
	rm -rf $(EXPORT_PATH)
	mkdir -p $(EXPORT_PATH)
	cp -R "$(ARCHIVE_PATH)/Products/Applications/GooseNeck.app" "$(APP_PATH)"
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_PATH)"

notarize: package
	test -n "$(NOTARY_PROFILE)"
	xcrun notarytool submit "$(ZIP_PATH)" --keychain-profile "$(NOTARY_PROFILE)" --wait

staple:
	xcrun stapler staple "$(APP_PATH)"
