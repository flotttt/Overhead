# Overhead — build without Xcode. See scripts/build.sh for the knobs.
DEBUG ?= 0

.PHONY: all build run test release install icon clean

all: build

build:
	DEBUG_PROTOCOL=$(DEBUG) ./scripts/build.sh

LOG_FILE := $(HOME)/Library/Logs/Overhead/app.log

run: build
	-pkill -x Overhead; while pgrep -x Overhead >/dev/null; do sleep 0.2; done
	@mkdir -p "$(dir $(LOG_FILE))"
	@ln -sfn "$(LOG_FILE)" "$(CURDIR)/build/app.log"
	@echo "=== Overhead session $$(date '+%Y-%m-%d %H:%M:%S') ===" >> "$(LOG_FILE)"
	open "$(CURDIR)/build/Overhead.app" --args -OverheadLogFile "$(LOG_FILE)"

test:
	./scripts/test.sh

release:
	CONFIG=release ARCHS="arm64 x86_64" ./scripts/build.sh
	cd build && rm -f Overhead.zip && ditto -c -k --keepParent Overhead.app Overhead.zip
	@# For SonyNotch 1.4 and older, whose updater only fetches SonyNotch.zip and installs the SonyNotch.app inside:
	@# the same app under that folder name (the signature doesn't cover it). Overhead renames itself at first launch.
	rm -rf build/legacy build/SonyNotch.zip && mkdir -p build/legacy
	ditto build/Overhead.app build/legacy/SonyNotch.app
	cd build/legacy && ditto -c -k --keepParent SonyNotch.app ../SonyNotch.zip

install: release
	-pkill -x Overhead; while pgrep -x Overhead >/dev/null; do sleep 0.2; done
	-pkill -x SonyNotch; pkill -x SonyBridge; rm -rf "/Applications/SonyNotch.app" "/Applications/SonyBridge.app"  # former names
	rm -rf "/Applications/Overhead.app"
	ditto "$(CURDIR)/build/Overhead.app" "/Applications/Overhead.app"
	open "/Applications/Overhead.app"

# Redraws the app icon (scripts/make_icon.swift) into the iconset the build uses.
icon:
	@mkdir -p build
	swiftc -O scripts/make_icon.swift -o build/make_icon
	build/make_icon Client/macos/Resources/AppIcon.iconset

clean:
	rm -rf build
