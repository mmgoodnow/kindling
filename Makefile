SHELL := /bin/bash

.PHONY: mac
mac:
	@xcodebuild -project kindling.xcodeproj -scheme kindling -destination 'platform=macOS' build
	@killall kindling >/dev/null 2>&1 || true
	@open -a ~/Library/Developer/Xcode/DerivedData/kindling-*/Build/Products/Debug/kindling.app

.PHONY: sim
sim:
	@xcodebuild -project kindling.xcodeproj -scheme kindling -destination 'platform=iOS Simulator,name=iPhone 17' build
	@xcrun simctl bootstatus "iPhone 17" -b
	@xcrun simctl install "iPhone 17" ~/Library/Developer/Xcode/DerivedData/kindling-*/Build/Products/Debug-iphonesimulator/kindling.app
	@xcrun simctl launch "iPhone 17" com.bebopbeluga.kindling
