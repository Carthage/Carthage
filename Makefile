#!/usr/bin/xcrun make -f

CARTHAGE_TEMPORARY_FOLDER?=/tmp/Carthage.dst
export CARTHAGE_TEMPORARY_FOLDER
PREFIX?=/usr/local
export PREFIX

INTERNAL_PACKAGE=CarthageApp.pkg
OUTPUT_PACKAGE=Carthage.pkg

CARTHAGE_EXECUTABLE=./.build/release/carthage
BINARIES_FOLDER=$(PREFIX)/bin
export BINARIES_FOLDER

SWIFT_BUILD_FLAGS=--configuration release -Xswiftc -suppress-warnings
SWIFT_TEST_FLAGS=--skip-update

SWIFTPM_DISABLE_SANDBOX_SHOULD_BE_FLAGGED:=$(shell test -n "$${HOMEBREW_SDKROOT}" && echo should_be_flagged)
ifeq ($(SWIFTPM_DISABLE_SANDBOX_SHOULD_BE_FLAGGED), should_be_flagged)
SWIFT_BUILD_FLAGS+= --disable-sandbox
endif
SWIFT_BUILD_SHOULD_BE_FLAGGED_VERY_VERBOSE:=$(shell (/usr/bin/xcrun --find swift-package | /bin/zsh --no-globalrcs --no-rcs -c '/usr/bin/strings "$$(cat)"' | grep --quiet -e '^veryVerbose') && echo should_be_flagged)
ifeq ($(SWIFT_BUILD_SHOULD_BE_FLAGGED_VERY_VERBOSE), should_be_flagged)
SWIFT_BUILD_FLAGS+= --very-verbose
SWIFT_TEST_FLAGS+= --very-verbose
endif
SWIFT_STATIC_STDLIB_SHOULD_BE_FLAGGED:=$(shell test -d $$(dirname $$(xcrun --find swift))/../lib/swift_static/macosx && (./script/strings_of_xcrun_find_ld.zsh | grep --quiet -e '^only one snapshot supported') && echo should_be_flagged)
ifeq ($(SWIFT_STATIC_STDLIB_SHOULD_BE_FLAGGED), should_be_flagged)
SWIFT_BUILD_FLAGS+= -Xswiftc -static-stdlib
endif

# ZSH_COMMAND · run single command in `zsh` shell, ignoring most `zsh` startup files.
ZSH_COMMAND = ZDOTDIR='/var/empty' zsh --no-globalrcs --no-rcs -c
# RM_SAFELY · `rm -rf` ensuring first and only parameter is non-null, contains more than whitespace, non-root if resolving absolutely.
RM_SAFELY = $(ZSH_COMMAND) '[[ ! $${1:?} =~ "^[[:space:]]+\$$" ]] && [[ $${1:A} != "/" ]] && [[ $${\#} == "1" ]] && noglob rm -rf $${1:A}' --

VERSION_STRING=$(shell git describe --abbrev=0 --tags)
DISTRIBUTION_PLIST=Source/carthage/Distribution.plist

RM=rm -f
SUDO=sudo
CP=cp

ifdef DISABLE_SUDO
override SUDO=
endif

.PHONY: all clean install package test uninstall xcconfig xcodeproj

all: installables

clean:
	swift package clean

test:
	$(RM_SAFELY) ./.build/debug/CarthagePackageTests.xctest
	swift build --build-tests -Xswiftc -suppress-warnings
	$(CP) -R Tests/CarthageKitTests/Resources ./.build/debug/CarthagePackageTests.xctest/Contents
	$(CP) Tests/CarthageKitTests/fixtures/CartfilePrivateOnly.zip ./.build/debug/CarthagePackageTests.xctest/Contents/Resources
	script/copy-fixtures ./.build/debug/CarthagePackageTests.xctest/Contents/Resources
	swift test --skip-build $(SWIFT_TEST_FLAGS)

installables:
	swift build $(SWIFT_BUILD_FLAGS)
	/bin/zsh --no-globalrcs --no-rcs -c 'set -x; print -r "$${CARTHAGE_TEMPORARY_FOLDER:?}$${BINARIES_FOLDER:?}"'

package: installables
	/bin/zsh --no-globalrcs --no-rcs -c 'set -x; mkdir -p "$${CARTHAGE_TEMPORARY_FOLDER:?}$${BINARIES_FOLDER:?}"'
	$(CP) -v "$(CARTHAGE_EXECUTABLE)" "$${CARTHAGE_TEMPORARY_FOLDER:?}$${BINARIES_FOLDER:?}"
	
	pkgbuild \
		--identifier "org.carthage.carthage" \
		--install-location "/" \
		--root "$${CARTHAGE_TEMPORARY_FOLDER:?}" \
		--version "$(VERSION_STRING)" \
		"$(INTERNAL_PACKAGE)"

	productbuild \
	  	--distribution "$(DISTRIBUTION_PLIST)" \
	  	--package-path "$(INTERNAL_PACKAGE)" \
	   	"$(OUTPUT_PACKAGE)"

prefix_install: installables
	/bin/zsh --no-globalrcs --no-rcs -c 'set -x; mkdir -p "$${BINARIES_FOLDER:?}"'
	$(CP) -v -f "$(CARTHAGE_EXECUTABLE)" "$${BINARIES_FOLDER:?}"

install: installables
	if [ ! -d "$${BINARIES_FOLDER:?}" ]; then $(SUDO) mkdir -p "$${BINARIES_FOLDER:?}"; fi
	$(SUDO) $(CP) -v -f "$(CARTHAGE_EXECUTABLE)" "$${BINARIES_FOLDER:?}"

uninstall:
	/bin/zsh --no-globalrcs --no-rcs -c 'set -x; rm -f -v "$${BINARIES_FOLDER:?}"'
	
xcodeproj:
	 swift package generate-xcodeproj
