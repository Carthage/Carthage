#!/usr/bin/env bats

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
