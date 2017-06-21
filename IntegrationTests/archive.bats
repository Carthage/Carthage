#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
    rm -rf Result
    git clone -b 3.1.0 https://github.com/antitypical/Result.git
    cd Result
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage archive errors unless carthage build --no-skip-current has been run" {
    run carthage archive
    [ "$status" -eq 1 ]
    [ "$output" = "Could not find any copies of Result.framework. Make sure you're in the project's root and that the frameworks have already been built using 'carthage build --no-skip-current'." ]
}

@test "carthage archive after carthage build --no-skip-current produces a zipped framework of all frameworks" {
    run carthage build --platform mac --no-skip-current
    [ "$status" -eq 0 ]
    run carthage archive
    [ "$status" -eq 0 ]
    [ -e Result.framework.zip ]
}

@test "carthage archive --output with a non-existing path ends with '/' should produce a zip file into the specified directory" {
    run carthage build --platform mac --no-skip-current
    [ "$status" -eq 0 ]
    rm -rf FooBar
    run carthage archive --output FooBar/
    [ "$status" -eq 0 ]
    [ -e FooBar/Result.framework.zip ]
}

@test "carthage archive --output with an existing directory path should produce a zip file into the specified directory" {
    run carthage build --platform mac --no-skip-current
    [ "$status" -eq 0 ]
    mkdir FooBar
    run carthage archive --output FooBar
    [ "$status" -eq 0 ]
    [ -e FooBar/Result.framework.zip ]
}

@test "carthage archive --output with a file path should produce a zip file at the given path" {
    run carthage build --platform mac --no-skip-current
    [ "$status" -eq 0 ]
    rm -rf FooBar
    run carthage archive --output FooBar/GreatName.framework.zip
    [ "$status" -eq 0 ]
    [ -e FooBar/GreatName.framework.zip ]
}
