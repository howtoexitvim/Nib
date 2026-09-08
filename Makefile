# Nib build.
#
#   make        build the web bundle and the .app
#   make run    build, then launch
#   make clean  remove build output
#
# The .app is assembled by hand rather than by Xcode so the whole thing builds
# from a terminal with no project file or IDE state.

APP      := build/Nib.app
BINARY   := .build/release/Nib
CONTENTS := $(APP)/Contents

.PHONY: all web swift app run test clean

all: app

# Both suites: the Swift side covers response handling and endpoints, the JS
# side covers the ghost-text trigger rules.
test:
	swift test
	cd web && npm test

web:
	cd web && npm run build

swift:
	swift build -c release

app: web swift
	rm -rf $(APP)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources/web
	cp $(BINARY) $(CONTENTS)/MacOS/Nib
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/Nib.icns $(CONTENTS)/Resources/Nib.icns
	# -R, not a plain glob: a subdirectory in dist/ would otherwise be skipped.
	cp -R web/dist/. $(CONTENTS)/Resources/web/
	# Ad-hoc signature: without one the Keychain item is tied to nothing stable
	# and macOS re-prompts for access on every launch.
	codesign --force --sign - --entitlements Resources/Nib.entitlements $(APP)
	@echo "built $(APP)"

run: app
	open $(APP)

clean:
	rm -rf build .build web/dist
