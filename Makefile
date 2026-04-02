.PHONY: generate build clean run archive package notarize staple

generate:
	xcodegen generate

build: generate
	xcodebuild -project PostureDesk.xcodeproj -scheme PostureDesk -configuration Debug build SYMROOT=$(CURDIR)/build

clean:
	xcodebuild -project PostureDesk.xcodeproj -scheme PostureDesk clean 2>/dev/null || true
	rm -rf build

run: build
	open build/Debug/PostureDesk.app

ARCHIVE_PATH ?= $(CURDIR)/build/PostureDesk.xcarchive
EXPORT_PATH ?= $(CURDIR)/build/release
APP_PATH ?= $(EXPORT_PATH)/PostureDesk.app
ZIP_PATH ?= $(EXPORT_PATH)/PostureDesk.zip
NOTARY_PROFILE ?=

archive: generate
	xcodebuild -project PostureDesk.xcodeproj -scheme PostureDesk -configuration Release archive -archivePath $(ARCHIVE_PATH)

package: archive
	rm -rf $(EXPORT_PATH)
	mkdir -p $(EXPORT_PATH)
	cp -R "$(ARCHIVE_PATH)/Products/Applications/PostureDesk.app" "$(APP_PATH)"
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_PATH)"

notarize: package
	test -n "$(NOTARY_PROFILE)"
	xcrun notarytool submit "$(ZIP_PATH)" --keychain-profile "$(NOTARY_PROFILE)" --wait

staple:
	xcrun stapler staple "$(APP_PATH)"
