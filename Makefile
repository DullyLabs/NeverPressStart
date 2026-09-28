APP := build/NeverPressStart.app
BIN_DIR = $(shell swift build -c release --show-bin-path)

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
	codesign --force --deep --sign - $(APP)

icon:
	rm -rf .build/AppIcon.iconset
	swift Support/Icon/make-icon.swift .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o Support/AppIcon.icns

run: app
	./$(APP)/Contents/MacOS/NeverPressStart

clean:
	rm -rf .build build
