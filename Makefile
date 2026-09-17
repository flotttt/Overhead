# SonyNotch — build without Xcode. See scripts/build.sh for the knobs.
DEBUG ?= 0

.PHONY: all build run test release install clean

all: build

build:
	DEBUG_PROTOCOL=$(DEBUG) ./scripts/build.sh

LOG_FILE := $(HOME)/Library/Logs/SonyNotch/app.log

run: build
	-pkill -x SonyNotch; while pgrep -x SonyNotch >/dev/null; do sleep 0.2; done
	@mkdir -p "$(dir $(LOG_FILE))"
	@ln -sfn "$(LOG_FILE)" "$(CURDIR)/build/app.log"
	@echo "=== SonyNotch session $$(date '+%Y-%m-%d %H:%M:%S') ===" >> "$(LOG_FILE)"
	open "$(CURDIR)/build/SonyNotch.app" --args -SonyNotchLogFile "$(LOG_FILE)"

test:
	./scripts/test.sh

release:
	CONFIG=release ARCHS="arm64 x86_64" ./scripts/build.sh
	cd build && rm -f SonyNotch.zip && ditto -c -k --keepParent SonyNotch.app SonyNotch.zip

install: release
	-pkill -x SonyNotch; while pgrep -x SonyNotch >/dev/null; do sleep 0.2; done
	-pkill -x SonyBridge; rm -rf "/Applications/SonyBridge.app"  # the app's former name
	rm -rf "/Applications/SonyNotch.app"
	ditto "$(CURDIR)/build/SonyNotch.app" "/Applications/SonyNotch.app"
	open "/Applications/SonyNotch.app"

clean:
	rm -rf build
