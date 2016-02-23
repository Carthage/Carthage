#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf Ra
    git clone https://github.com/younata/Ra.git
    cd Ra
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage update builds everything" {
    run carthage update --no-use-binaries
    [ "$status" -eq 0 ]
    [ -e Carthage/Build/iOS/Quick.framework ]
    [ -e Carthage/Build/iOS/Nimble.framework ]
    [ -e Carthage/Build/Mac/Quick.framework ]
    [ -e Carthage/Build/Mac/Nimble.framework ]
    [ -e Carthage/Build/tvOS/Quick.framework ]
    [ -e Carthage/Build/tvOS/Nimble.framework ]
    [ -e Carthage/Build/watchOS/Quick.framework ]
    [ -e Carthage/Build/watchOS/Nimble.framework ]
}
