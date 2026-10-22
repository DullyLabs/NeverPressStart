APP := build/NeverPressStart.app
BIN_DIR = $(shell swift build -c release --show-bin-path)
# First Apple Development certificate in the keychain; ad hoc ("-") if there is none.
SIGN_ID ?= $(shell security find-identity -v -p codesigning | awk '/Apple Development/ {print $$2; exit}')

.PHONY: all build app icon run clean

all: app

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$(BIN_DIR)/NeverPressStart" $(APP)/Contents/MacOS/NeverPressStart
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp Support/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Support/BreakChime.m4a $(APP)/Contents/Resources/BreakChime.m4a
	codesign --force --options runtime --entitlements Support/NeverPressStart.entitlements \
		--sign "$(or $(SIGN_ID),-)" $(APP)

icon:
	rm -rf .build/AppIcon.iconset
	swift Support/Icon/make-icon.swift .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o Support/AppIcon.icns

run: app
	./$(APP)/Contents/MacOS/NeverPressStart

clean:
	rm -rf .build build
