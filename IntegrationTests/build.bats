#!/usr/bin/env bats

load "Utilities/TestFramework"

setup() {
    cd $BATS_TMPDIR
}

teardown() {
    cd $BATS_TEST_DIRNAME
}

@test "carthage build skips dependencies with no shared schemes" {
    cat >| Cartfile <<-EOF
github "AFNetworking/AFNetworking" == 2.6.3
github "mdiep/MMMarkdown" == 0.5.5
EOF
    run carthage bootstrap --platform ios
    [ "$status" -eq 0 ]
    [ -e Carthage/Build/iOS/MMMarkdown.framework ]
}

@test "carthage build --no-skip-current caches the current project" {
    extract-workspace-with-dependency
    cd "${BATS_TMPDIR:?}/WorkspaceWithDependency"
    git init && git-commit 'Initialize project.'
    git remote add origin "git@example.com:TestFramework1.git"

    run carthage build --no-skip-current --platform mac --cache-builds
    [ "$status" -eq 0 ]
    [[ "$output" =~ "*** Invalid cache found for TestFramework1, rebuilding with all downstream dependencies" ]]

    run carthage build --no-skip-current --platform mac --cache-builds
    [ "$status" -eq 0 ]
    [[ "$output" =~ "*** Valid cache found for TestFramework1, skipping build" ]]
}
