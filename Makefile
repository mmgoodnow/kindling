SHELL := /bin/bash

.PHONY: run
run:
	@osascript -e 'tell application "System Events" to set frontApp to name of first application process whose frontmost is true' \
		-e 'tell application "Xcode" to activate' \
		-e 'tell application "System Events" to keystroke "r" using {command down}' \
		-e 'tell application frontApp to activate'

.PHONY: sim
sim:
	@xcodebuild -project kindling.xcodeproj -scheme kindling -destination 'platform=iOS Simulator,name=iPhone 17' build
	@xcrun simctl bootstatus "iPhone 17" -b
	@xcrun simctl install "iPhone 17" ~/Library/Developer/Xcode/DerivedData/kindling-*/Build/Products/Debug-iphonesimulator/kindling.app
	@xcrun simctl launch "iPhone 17" com.bebopbeluga.kindling
