#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf Argo
    git clone -b v2.3.0 https://github.com/thoughtbot/Argo.git
    cd Argo
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage update builds everything" {
    run carthage update --platform mac --no-use-binaries
    [ "$status" -eq 0 ]
    [ -e Carthage/Build/Mac/Curry.framework ]
    [ -e Carthage/Build/Mac/Runes.framework ]
}
