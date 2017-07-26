import Foundation
import PackageDescription

var isSwiftPackagerManagerTest: Bool {
    return ProcessInfo.processInfo.environment["SWIFTPM_TEST_Carthage"] == "YES"
}

let package = Package(
    name: "Carthage",
    targets: [
        Target(name: "XCDBLD"),
        Target(name: "CarthageKit", dependencies: [ "XCDBLD" ]),
        Target(name: "carthage", dependencies: [ "XCDBLD", "CarthageKit" ]),
    ],
    dependencies: {
        var deps: [Package.Dependency] = [
            .Package(url: "https://github.com/antitypical/Result.git", versions: Version(3, 2, 1)..<Version(3, .max, .max)),
            .Package(url: "https://github.com/Carthage/ReactiveTask.git", majorVersion: 0, minor: 13),
            .Package(url: "https://github.com/Carthage/Commandant.git", majorVersion: 0, minor: 12),
            .Package(url: "https://github.com/jdhealy/PrettyColors.git", majorVersion: 5),
            .Package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", majorVersion: 2),
            .Package(url: "https://github.com/mdiep/Tentacle.git", majorVersion: 0, minor: 8),
            .Package(url: "https://github.com/thoughtbot/Argo.git", majorVersion: 4, minor: 1),
            .Package(url: "https://github.com/thoughtbot/Runes.git", versions: Version(4, 0, 1)..<Version(4, .max, .max)),
        ]
        if isSwiftPackagerManagerTest {
            deps += [
                .Package(url: "https://github.com/Quick/Quick.git", majorVersion: 1, minor: 1),
                .Package(url: "https://github.com/Quick/Nimble.git", majorVersion: 7),
            ]
        }
        return deps
    }(),
    exclude: [
        "Source/Scripts",
        "Source/carthage/swift-is-crashy.c",
        "Tests/CarthageKitTests/Resources/FakeOldObjc.framework",
    ]
)
