# MarkyQL — command-line build (no Xcode IDE required).
#
#   make            build MarkyQL.app (with the Quick Look extension) and the CLI
#   make install    copy the app to /Applications, launch it once, reset Quick Look
#   make uninstall  remove the app
#   make test-render  render examples/feature-test.md to build/feature-test.html
#   make clean
#
# Signing: ad-hoc by default (fine for local use). For distribution set
# SIGN_ID to a Developer ID identity, e.g.
#   make SIGN_ID="Developer ID Application: Your Name (TEAMID)"
#
# Requires: Xcode Command Line Tools (clang, macOS SDK) and cmake
# (`brew install cmake`). Network access on first build: the cmark-gfm
# submodule and the pinned JS dependencies are fetched then.

APP_NAME    := MarkyQL
BUILD       := build
APP         := $(BUILD)/$(APP_NAME).app
APPEX       := $(APP)/Contents/PlugIns/$(APP_NAME).appex
DEPLOYMENT  := 12.0
ARCHFLAGS   := -arch arm64 -arch x86_64
SDK         := $(shell xcrun --show-sdk-path)
CC          := xcrun clang
SIGN_ID     ?= -

CMARK_DIR   := vendor/cmark-gfm
CMARK_BUILD := $(BUILD)/cmark-gfm
CMARK_LIBS  := $(CMARK_BUILD)/src/libcmark-gfm.a \
               $(CMARK_BUILD)/extensions/libcmark-gfm-extensions.a
CMARK_INC   := -I$(CMARK_DIR)/src -I$(CMARK_DIR)/extensions \
               -I$(CMARK_BUILD)/src -I$(CMARK_BUILD)/extensions

BASEFLAGS   := -isysroot $(SDK) -mmacosx-version-min=$(DEPLOYMENT) \
               $(ARCHFLAGS) -O2 -Wno-deprecated-declarations
OBJCFLAGS   := $(BASEFLAGS) -fobjc-arc -IShared $(CMARK_INC)
CFLAGS      := $(BASEFLAGS) -IShared $(CMARK_INC)

SHARED_SRC  := Shared/MQSettings.m Shared/MQRenderer.m Shared/MQMarkdown.c

.PHONY: all app cli js cmark install uninstall test-render check clean
all: app cli

# ---------------------------------------------------------------- cmark-gfm
cmark: $(CMARK_LIBS)
$(CMARK_LIBS):
	@test -f $(CMARK_DIR)/CMakeLists.txt || { \
		echo "cmark-gfm submodule missing; fetching…"; \
		git submodule update --init vendor/cmark-gfm || \
		git clone https://github.com/github/cmark-gfm.git $(CMARK_DIR); }
	cmake -S $(CMARK_DIR) -B $(CMARK_BUILD) \
		-DCMAKE_BUILD_TYPE=Release -DCMARK_TESTS=OFF -DCMARK_SHARED=OFF \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-DCMAKE_OSX_SYSROOT=$(SDK)
	cmake --build $(CMARK_BUILD) -j

# ---------------------------------------------------------------- JS deps
js:
	@sh scripts/fetch-js.sh

# ---------------------------------------------------------------- binaries
$(BUILD)/MarkyQLPreview: QLExtension/MQPreviewController.m $(SHARED_SRC) $(CMARK_LIBS)
	@mkdir -p $(BUILD)
	$(CC) $(OBJCFLAGS) -o $@ QLExtension/MQPreviewController.m $(SHARED_SRC) \
		$(CMARK_LIBS) -bundle -e _NSExtensionMain \
		-framework Cocoa -framework Quartz -framework WebKit

$(BUILD)/MarkyQL: App/main.m App/MQAppDelegate.m $(SHARED_SRC) $(CMARK_LIBS)
	@mkdir -p $(BUILD)
	$(CC) $(OBJCFLAGS) -o $@ App/main.m App/MQAppDelegate.m $(SHARED_SRC) \
		$(CMARK_LIBS) -framework Cocoa -framework WebKit

$(BUILD)/markyql: CLI/main.m $(SHARED_SRC) $(CMARK_LIBS)
	@mkdir -p $(BUILD)
	$(CC) $(OBJCFLAGS) -o $@ CLI/main.m $(SHARED_SRC) \
		$(CMARK_LIBS) -framework Foundation

cli: $(BUILD)/markyql

# ---------------------------------------------------------------- app bundle
app: $(BUILD)/MarkyQL $(BUILD)/MarkyQLPreview $(BUILD)/markyql js
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources \
		$(APPEX)/Contents/MacOS $(APPEX)/Contents/Resources
	cp App/Info.plist $(APP)/Contents/Info.plist
	cp $(BUILD)/MarkyQL $(APP)/Contents/MacOS/MarkyQL
	cp $(BUILD)/markyql $(APP)/Contents/MacOS/markyql
	cp QLExtension/Info.plist $(APPEX)/Contents/Info.plist
	cp $(BUILD)/MarkyQLPreview $(APPEX)/Contents/MacOS/MarkyQLPreview
	cp -R Resources/themes Resources/js $(APP)/Contents/Resources/
	cp -R Resources/themes Resources/js $(APPEX)/Contents/Resources/
	codesign --force --timestamp=none --sign "$(SIGN_ID)" \
		--entitlements QLExtension/MarkyQLPreview.entitlements $(APPEX)
	codesign --force --timestamp=none --sign "$(SIGN_ID)" \
		$(APP)/Contents/MacOS/markyql
	codesign --force --timestamp=none --sign "$(SIGN_ID)" \
		--entitlements App/MarkyQL.entitlements $(APP)
	@echo "Built $(APP)"

# ---------------------------------------------------------------- misc
install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	open /Applications/$(APP_NAME).app
	@sleep 2
	pluginkit -e use -i com.markyql.app.preview >/dev/null 2>&1 || true
	qlmanage -r >/dev/null 2>&1 || true
	@echo "Installed. Select a .md file in Finder and press Space."

uninstall:
	rm -rf /Applications/$(APP_NAME).app
	qlmanage -r >/dev/null 2>&1 || true

test-render: $(BUILD)/markyql js
	MARKYQL_RESOURCES=$(CURDIR)/Resources $(BUILD)/markyql \
		examples/feature-test.md -o $(BUILD)/feature-test.html
	@echo "Wrote $(BUILD)/feature-test.html"

check:
	plutil -lint App/Info.plist QLExtension/Info.plist \
		App/MarkyQL.entitlements QLExtension/MarkyQLPreview.entitlements
	sh -n scripts/fetch-js.sh

clean:
	rm -rf $(BUILD)
