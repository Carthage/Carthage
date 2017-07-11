TEMPORARY_FOLDER?=/tmp/Carthage.dst
PREFIX?=/usr/local

XCODEFLAGS=-workspace 'Carthage.xcworkspace' -scheme 'carthage' DSTROOT=$(TEMPORARY_FOLDER)

INTERNAL_PACKAGE=CarthageApp.pkg
OUTPUT_PACKAGE=Carthage.pkg
OUTPUT_FRAMEWORK=CarthageKit.framework
OUTPUT_FRAMEWORK_ZIP=CarthageKit.framework.zip

BUILT_BUNDLE=$(TEMPORARY_FOLDER)/Applications/carthage.app
CARTHAGEKIT_BUNDLE=$(BUILT_BUNDLE)/Contents/Frameworks/$(OUTPUT_FRAMEWORK)
CARTHAGE_EXECUTABLE=$(BUILT_BUNDLE)/Contents/MacOS/carthage

FRAMEWORKS_FOLDER=/Library/Frameworks
BINARIES_FOLDER=/usr/local/bin

VERSION_STRING=$(shell git describe --abbrev=0 --tags)
COMPONENTS_PLIST=Source/carthage/Components.plist
DISTRIBUTION_PLIST=Source/carthage/Distribution.plist

.PHONY: all bootstrap clean install package test uninstall

all: bootstrap
	xcodebuild $(XCODEFLAGS) build

bootstrap:
	git submodule update --init --recursive

test: clean bootstrap
	xcodebuild $(XCODEFLAGS) -configuration Release ENABLE_TESTABILITY=YES test

clean:
	rm -f "$(INTERNAL_PACKAGE)"
	rm -f "$(OUTPUT_PACKAGE)"
	rm -f "$(OUTPUT_FRAMEWORK_ZIP)"
	rm -rf "$(TEMPORARY_FOLDER)"
	xcodebuild $(XCODEFLAGS) clean

install: package
	sudo installer -pkg $(OUTPUT_PACKAGE) -target /

uninstall:
	rm -rf "$(FRAMEWORKS_FOLDER)/$(OUTPUT_FRAMEWORK)"
	rm -f "$(BINARIES_FOLDER)/carthage"

installables: clean bootstrap
	xcodebuild $(XCODEFLAGS) install

	mkdir -p "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)"
	mv -f "$(CARTHAGEKIT_BUNDLE)" "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/$(OUTPUT_FRAMEWORK)"
	mv -f "$(CARTHAGE_EXECUTABLE)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage"
	rm -rf "$(BUILT_BUNDLE)"

prefix_install: installables
	mkdir -p "$(PREFIX)/Frameworks" "$(PREFIX)/bin"
	rsync -a --delete "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/$(OUTPUT_FRAMEWORK)" "$(PREFIX)/Frameworks/"
	cp -f "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage" "$(PREFIX)/bin/"
	install_name_tool -rpath "/Library/Frameworks" "@executable_path/../Frameworks/$(OUTPUT_FRAMEWORK)/Versions/Current/Frameworks/"  "$(PREFIX)/bin/carthage"

package: installables
	pkgbuild \
		--component-plist "$(COMPONENTS_PLIST)" \
		--identifier "org.carthage.carthage" \
		--install-location "/" \
		--root "$(TEMPORARY_FOLDER)" \
		--version "$(VERSION_STRING)" \
		"$(INTERNAL_PACKAGE)"

	productbuild \
  	--distribution "$(DISTRIBUTION_PLIST)" \
  	--package-path "$(INTERNAL_PACKAGE)" \
   	"$(OUTPUT_PACKAGE)"

	(cd "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" && zip -q -r --symlinks - "$(OUTPUT_FRAMEWORK)") > "$(OUTPUT_FRAMEWORK_ZIP)"

swiftpm:
	swift build -c release -Xswiftc -static-stdlib

swiftpm_test:
	rm -rf ./.build/debug/CarthagePackageTests.xctest
	SWIFTPM_TEST_Carthage=YES swift test --specifier "" # Make SwiftPM just build the test bundle without running it
	cp -R Tests/CarthageKitTests/Resources ./.build/debug/CarthagePackageTests.xctest/Contents
	cp Tests/CarthageKitTests/fixtures/CartfilePrivateOnly.zip ./.build/debug/CarthagePackageTests.xctest/Contents/Resources
	script/copy-fixtures ./.build/debug/CarthagePackageTests.xctest/Contents/Resources
	SWIFTPM_TEST_Carthage=YES swift test --skip-build

swiftpm_install: swiftpm
	mkdir -p "$(PREFIX)/bin"
	cp -f ./.build/release/carthage "$(PREFIX)/bin/"
