#!/usr/bin/xcrun make -f

CARTHAGE_TEMPORARY_FOLDER?=/tmp/Carthage.dst
PREFIX?=/usr/local

XCODEFLAGS=-workspace 'Carthage.xcworkspace' -scheme 'carthage' DSTROOT=$(CARTHAGE_TEMPORARY_FOLDER) OTHER_LDFLAGS=-Wl,-headerpad_max_install_names 

INTERNAL_PACKAGE=CarthageApp.pkg
OUTPUT_PACKAGE=Carthage.pkg
OUTPUT_FRAMEWORK=CarthageKit.framework
OUTPUT_FRAMEWORK_ZIP=CarthageKit.framework.zip

BUILT_BUNDLE=$(CARTHAGE_TEMPORARY_FOLDER)/Applications/carthage.app
CARTHAGEKIT_BUNDLE=$(BUILT_BUNDLE)/Contents/Frameworks/$(OUTPUT_FRAMEWORK)
CARTHAGE_EXECUTABLE=$(BUILT_BUNDLE)/Contents/MacOS/carthage

FRAMEWORKS_FOLDER=/Library/Frameworks
BINARIES_FOLDER=/usr/local/bin

# ZSH_COMMAND · run single command in `zsh` shell, ignoring most `zsh` startup files.
ZSH_COMMAND := ZDOTDIR='/var/empty' zsh -o NO_GLOBAL_RCS -c
# RM_SAFELY · `rm -rf` ensuring first and only parameter is non-null, contains more than whitespace, non-root if resolving absolutely.
RM_SAFELY := $(ZSH_COMMAND) '[[ ! $${1:?} =~ "^[[:space:]]+\$$" ]] && [[ $${1:A} != "/" ]] && [[ $${\#} == "1" ]] && noglob rm -rf $${1:A}' --

VERSION_STRING=$(shell git describe --abbrev=0 --tags)
COMPONENTS_PLIST=Source/carthage/Components.plist
DISTRIBUTION_PLIST=Source/carthage/Distribution.plist

RM=rm -f
RMD=rm -rf
MKDIR=mkdir -p
SUDO=sudo
MV=mv -f
CP=cp
RSYNC=rsync -a --delete

.PHONY: all bootstrap clean install package test uninstall

all: bootstrap
	xcodebuild $(XCODEFLAGS) build

bootstrap:
	git submodule update --init --recursive

test: clean bootstrap
	xcodebuild $(XCODEFLAGS) -configuration Release ENABLE_TESTABILITY=YES test

clean:
	$(RM) "$(INTERNAL_PACKAGE)"
	$(RM) "$(OUTPUT_PACKAGE)"
	$(RM) "$(OUTPUT_FRAMEWORK_ZIP)"
	$(RM_SAFELY) "$(CARTHAGE_TEMPORARY_FOLDER)"
	xcodebuild $(XCODEFLAGS) clean

install: package
	$(SUDO) installer -pkg $(OUTPUT_PACKAGE) -target /

uninstall:
	$(RM_SAFELY) "$(FRAMEWORKS_FOLDER)/$(OUTPUT_FRAMEWORK)"
	$(RM) "$(BINARIES_FOLDER)/carthage"

installables: clean bootstrap
	xcodebuild $(XCODEFLAGS) install

	$(MKDIR) "$(CARTHAGE_TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" "$(CARTHAGE_TEMPORARY_FOLDER)$(BINARIES_FOLDER)"
	$(MV) "$(CARTHAGEKIT_BUNDLE)" "$(CARTHAGE_TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/$(OUTPUT_FRAMEWORK)"
	$(MV) "$(CARTHAGE_EXECUTABLE)" "$(CARTHAGE_TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage"
	$(RM_SAFELY) "$(BUILT_BUNDLE)"

prefix_install: installables
	$(MKDIR) "$(PREFIX)/Frameworks" "$(PREFIX)/bin"
	$(RSYNC) "$(CARTHAGE_TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/$(OUTPUT_FRAMEWORK)" "$(PREFIX)/Frameworks/"
	$(CP) -f "$(CARTHAGE_TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage" "$(PREFIX)/bin/"
	install_name_tool -delete_rpath "@executable_path/../Frameworks" "$(PREFIX)/bin/carthage" # Avoid duplication of "@executable_path/../Frameworks"
	install_name_tool -rpath "/Library/Frameworks" "@executable_path/../Frameworks" "$(PREFIX)/bin/carthage"
	install_name_tool -rpath "/Library/Frameworks/CarthageKit.framework/Versions/Current/Frameworks" "@executable_path/../Frameworks/CarthageKit.framework/Versions/Current/Frameworks" "$(PREFIX)/bin/carthage"

package: installables
	pkgbuild \
		--component-plist "$(COMPONENTS_PLIST)" \
		--identifier "org.carthage.carthage" \
		--install-location "/" \
		--root "$(CARTHAGE_TEMPORARY_FOLDER)" \
		--version "$(VERSION_STRING)" \
		"$(INTERNAL_PACKAGE)"

	productbuild \
  	--distribution "$(DISTRIBUTION_PLIST)" \
  	--package-path "$(INTERNAL_PACKAGE)" \
   	"$(OUTPUT_PACKAGE)"

	(cd "$(CARTHAGE_TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" && zip -q -r --symlinks - "$(OUTPUT_FRAMEWORK)") > "$(OUTPUT_FRAMEWORK_ZIP)"

swiftpm:
	swift build -c release -Xswiftc -static-stdlib -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.11"

swiftpm_test:
	$(RM_SAFELY) ./.build/debug/CarthagePackageTests.xctest
	swift build --build-tests -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.11"
	$(CP) -R Tests/CarthageKitTests/Resources ./.build/debug/CarthagePackageTests.xctest/Contents
	$(CP) Tests/CarthageKitTests/fixtures/CartfilePrivateOnly.zip ./.build/debug/CarthagePackageTests.xctest/Contents/Resources
	script/copy-fixtures ./.build/debug/CarthagePackageTests.xctest/Contents/Resources
	swift test --skip-build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.11"

swiftpm_install: swiftpm
	$(MKDIR) "$(PREFIX)/bin"
	$(CP) -f ./.build/release/carthage "$(PREFIX)/bin/"
