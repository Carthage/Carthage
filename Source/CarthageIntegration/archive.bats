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

@test "carthage archive errors unless carthage build --no-skip-current has been run" {
    run carthage archive
    [ "$status" -eq 1 ]
    [ "$output" = "Could not find any copies of Ra.framework. Make sure you're in the project’s root and that the frameworks have already been built using 'carthage build --no-skip-current'." ]
}

@test "carthage archive after carthage build --no-skip-current produces a zipped framework of all frameworks" {
    run carthage build --no-skip-current
    [ "$status" -eq 0 ]
    run carthage archive
    [ "$status" -eq 0 ]
    [ -e Ra.framework.zip ]
}

build_carthage() {
    make installables >&2
}

build_carthage
