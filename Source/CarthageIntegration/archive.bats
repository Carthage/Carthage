#!/usr/bin/env bats

@test "carthage archive errors unless carthage build --no-skip-current has been run" {
    pushd $BATS_TMPDIR
    rm -rf Ra
    git clone https://github.com/younata/Ra.git >&2
    cd Ra
    run carthage archive
    [ "$status" -eq 1 ]
    [ "$output" = "Could not find any copies of Ra.framework. Make sure you're in the project’s root and that the frameworks have already been built using 'carthage build --no-skip-current'." ]
    popd
}

@test "carthage archive after carthage build --no-skip-current produces a zipped framework of all frameworks" {
    pushd $BATS_TMPDIR
    rm -rf Ra
    git clone https://github.com/younata/Ra.git >&2
    cd Ra
    run carthage build --no-skip-current
    [ "$status" -eq 0 ]
    run carthage archive
    [ "$status" -eq 0 ]
    [ -e Ra.framework.zip ]
    popd
}
