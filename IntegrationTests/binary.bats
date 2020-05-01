#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf BinaryTest
    mkdir BinaryTest && cd BinaryTest
    echo 'binary "https://dl.google.com/dl/firebase/ios/carthage/FirebaseAnalyticsBinary.json" == 6.8.1' > Cartfile
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage update builds everything (binary)" {
    run carthage update --platform iOS

    [ "$status" -eq 0 ]
    [ -d Carthage/Build/iOS/FirebaseAnalytics.framework ]
}



