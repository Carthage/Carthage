XCODEFLAGS=-workspace 'Carthage.xcworkspace' -scheme 'carthage'

TEMPORARY_FOLDER=/tmp/Carthage.dst
BUILT_BUNDLE=$(TEMPORARY_FOLDER)/Applications/carthage.app
CARTHAGEKIT_BUNDLE=$(BUILT_BUNDLE)/Contents/Frameworks/CarthageKit.framework
CARTHAGE_EXECUTABLE=$(BUILT_BUNDLE)/Contents/MacOS/carthage

FRAMEWORKS_FOLDER=/Library/Frameworks
BINARIES_FOLDER=/usr/local/bin

OUTPUT_PACKAGE=Carthage.pkg

all: bootstrap
	xcodebuild $(XCODEFLAGS) build

bootstrap:
	script/bootstrap

clean:
	rm -f "$(OUTPUT_PACKAGE)"
	rm -rf "$(TEMPORARY_FOLDER)"
	xcodebuild $(XCODEFLAGS) clean

install: clean bootstrap
	xcodebuild $(XCODEFLAGS) install

	mkdir -p "$(FRAMEWORKS_FOLDER)"
	rm -rf "$(FRAMEWORKS_FOLDER)/CarthageKit.framework"
	cp -PR "$(CARTHAGEKIT_BUNDLE)" "$(FRAMEWORKS_FOLDER)/"

	install -d "$(BINARIES_FOLDER)"
	install -CSs "$(CARTHAGE_EXECUTABLE)" "$(BINARIES_FOLDER)/"

package: clean bootstrap
	xcodebuild $(XCODEFLAGS) install

	mkdir -p "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)"
	mv -f "$(CARTHAGEKIT_BUNDLE)" "$(TEMPORARY_FOLDER)$(FRAMEWORKS_FOLDER)/CarthageKit.framework"
	mv -f "$(CARTHAGE_EXECUTABLE)" "$(TEMPORARY_FOLDER)$(BINARIES_FOLDER)/carthage"
	rm -rf "$(BUILT_BUNDLE)"

	productbuild --root "$(TEMPORARY_FOLDER)" "/" --identifier "org.carthage.carthage" "$(OUTPUT_PACKAGE)"
