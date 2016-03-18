#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf Ra
    git clone -b v1.0.0 https://github.com/younata/Ra.git
    cd Ra
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage update builds everything" {
    run carthage update --platform mac --no-use-binaries
    [ "$status" -eq 0 ]
    [ -e Carthage/Build/Mac/Quick.framework ]
    [ -e Carthage/Build/Mac/Nimble.framework ]
}
