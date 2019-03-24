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

@test "carthage build works right IN MY SPECIAL SCENARIO WHICH NEEDS TO BE DESCRIBED HERE" {
cat >| Cartfile <<-EOF
github "ReactiveX/RxSwift" ~> 4.0
EOF
run carthage update
rm -rf Carthage/Build
run carthage build
[ "$status" -eq 0 ]
[ -e Carthage/Build/Mac/RxSwift.framework ]
}
