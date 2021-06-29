#!/usr/bin/env bats

setup() {
    cd $BATS_TMPDIR
}

teardown() {
    rm -f Cartfile Cartfile.resolved
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

@test "carthage build downloads multiple github release assets" {
    cat >| Cartfile <<-EOF
github "ReactiveX/RxSwift" == 6.1.0
EOF
    run carthage bootstrap --platform ios --use-xcframeworks
    [ "$status" -eq 0 ]
    [ -e Carthage/Build/RxTest.xcframework ]
    [ -e Carthage/Build/RxSwift.xcframework ]
    [ -e Carthage/Build/RxCocoaRuntime.xcframework ]
    [ -e Carthage/Build/RxCocoa.xcframework ]
    [ -e Carthage/Build/RxBlocking.xcframework ]
}
