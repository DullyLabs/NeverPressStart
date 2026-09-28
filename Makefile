APP := build/NeverPressStart.app
BIN_DIR = $(shell swift build -c release --show-bin-path)

.PHONY: all build app run clean

all: app

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp "$(BIN_DIR)/NeverPressStart" $(APP)/Contents/MacOS/NeverPressStart
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)

run: app
	./$(APP)/Contents/MacOS/NeverPressStart

clean:
	rm -rf .build build
