.PHONY: generate build clean run

generate:
	xcodegen generate

build: generate
	xcodebuild -project PostureDesk.xcodeproj -scheme PostureDesk -configuration Debug build SYMROOT=$(CURDIR)/build

clean:
	xcodebuild -project PostureDesk.xcodeproj -scheme PostureDesk clean 2>/dev/null || true
	rm -rf build

run: build
	open build/Debug/PostureDesk.app

daemon-test: build
	sudo build/Debug/PostureDesk.app/Contents/Library/HelperTools/PostureSensorDaemon
