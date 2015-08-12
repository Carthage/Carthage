TEMPORARY_FOLDER?=/tmp/Carthage.dst
PREFIX?=/usr/local
BUILD_TOOL?=xcodebuild

XCODEFLAGS=-workspace 'Carthage.xcworkspace' -scheme 'carthage' DSTROOT=$(TEMPORARY_FOLDER)

OUTPUT_PACKAGE=Carthage.pkg
OUTPUT_FRAMEWORKS=$(CARTHAGEKIT_FRAMEWORK) Commandant.framework PrettyColors.framework
CARTHAGEKIT_FRAMEWORK=CarthageKit.framework
CARTHAGEKIT_FRAMEWORK_ZIP=$(CARTHAGEKIT_FRAMEWORK).zip

BUILT_BUNDLE=$(TEMPORARY_FOLDER)/Applications/carthage.app
CARTHAGE_FRAMEWORKS=$(OUTPUT_FRAMEWORKS:%="$(BUILT_BUNDLE)/Contents/Frameworks/%")
CARTHAGE_EXECUTABLE=$(BUILT_BUNDLE)/Contents/MacOS/carthage

FRAMEWORKS_FOLDER=/Library/Frameworks
BINARIES_FOLDER=/usr/local/bin

VERSION_STRING=$(shell agvtool what-marketing-version -terse1)
COMPONENTS_PLIST=Source/carthage/Components.plist

.PHONY: all bootstrap clean install package test uninstall

all: bootstrap
	$(BUILD_TOOL) $(XCODEFLAGS) build

bootstrap:
	script/bootstrap

test: clean bootstrap
	$(BUILD_TOOL) $(XCODEFLAGS) test

clean:
	rm -f "$(OUTPUT_PACKAGE)"
	rm -f "$(CARTHAGEKIT_FRAMEWORK_ZIP)"
	rm -rf "$(TEMPORARY_FOLDER)"
	$(BUILD_TOOL) $(XCODEFLAGS) clean

install: package
	sudo installer -pkg Carthage.pkg -target /

uninstall:
	rm -rf $(OUTPUT_FRAMEWORKS:%="$(FRAMEWORKS_FOLDER)/%")
	rm -f "$(BINARIES_FOLDER)/carthage"

installables: clean bootstrap
	$(BUILD_TOOL) $(XCODEFLAGS) install

	mkdir -p "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)"
	mv -f $(CARTHAGE_FRAMEWORKS) "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/"
	mv -f "$(CARTHAGE_EXECUTABLE)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage"
	rm -rf "$(BUILT_BUNDLE)"

prefix_install: installables
	mkdir -p "$(PREFIX)/Frameworks" "$(PREFIX)/bin"
	cp -rf $(OUTPUT_FRAMEWORKS:%="$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/%") "$(PREFIX)/Frameworks/"
	cp -f "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage" "$(PREFIX)/bin/"
	$(foreach framework,$(OUTPUT_FRAMEWORKS),install_name_tool -add_rpath "@executable_path/../Frameworks/$(framework)/Versions/Current/Frameworks/" "$(PREFIX)/bin/carthage")

package: installables
	pkgbuild \
		--component-plist "$(COMPONENTS_PLIST)" \
		--identifier "org.carthage.carthage" \
		--install-location "/" \
		--root "$(TEMPORARY_FOLDER)" \
		--version "$(VERSION_STRING)" \
		"$(OUTPUT_PACKAGE)"
	
	(cd "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" && zip -q -r --symlinks - "$(CARTHAGEKIT_FRAMEWORK)") > "$(CARTHAGEKIT_FRAMEWORK_ZIP)"
