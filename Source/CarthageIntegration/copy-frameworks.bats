#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf CarthageCopyFrameworksFixture
    git clone -b 2.0.0 https://github.com/ikesyo/CarthageCopyFrameworksFixture.git
    cd CarthageCopyFrameworksFixture
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage copy-frameworks should work for all an app target, a unit test target, a UI test target and produce a valid xcarchive file" {
    run carthage update --platform ios
    [ "$status" -eq 0 ]

    run xcodebuild clean build-for-testing -scheme CarthageCopyFrameworksFixture -sdk iphonesimulator -destination "name=iPhone 6s"
    [ "$status" -eq 0 ]

    ARCHIVE_APP_DIR=CarthageCopyFrameworksFixture.xcarchive/Products/Applications
    run xcodebuild clean archive -scheme CarthageCopyFrameworksFixture -archivePath CarthageCopyFrameworksFixture.xcarchive CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
    [ "$status" -eq 0 ]
    [ -e "$ARCHIVE_APP_DIR/CarthageCopyFrameworksFixture.app" ]
    [ ! -e "$ARCHIVE_APP_DIR/Result.framework.dSYM" ]
    find "$ARCHIVE_APP_DIR" -name "*.bcsymbolmap" | xargs -n1 test ! -e
}
