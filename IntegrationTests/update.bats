#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf UpdateTest
    mkdir UpdateTest && cd UpdateTest
    echo 'github "antitypical/Result" == 4.1.0' > Cartfile
    echo 'github "Quick/Nimble" == 7.3.1' > Cartfile.private
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage update builds everything" {
    run carthage update --platform mac --no-use-binaries
    [ "$status" -eq 0 ]
    [ -e Carthage/Build/Mac/Result.framework ]
    [ -e Carthage/Build/Mac/Nimble.framework ]
}
