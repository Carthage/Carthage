import PackageDescription

let package = Package(
    name: "Carthage",
    targets: [
        Target(name: "XCDBLD"),
        Target(name: "CarthageKit", dependencies: [ "XCDBLD" ]),
        Target(name: "carthage", dependencies: [ "XCDBLD", "CarthageKit" ]),
    ],
    dependencies: [
        .Package(url: "https://github.com/antitypical/Result.git", majorVersion: 3, minor: 2),
        .Package(url: "https://github.com/Carthage/ReactiveTask.git", versions: Version(0, 11, 1)..<Version(0, 11, .max)),
        .Package(url: "https://github.com/Carthage/Commandant.git", majorVersion: 0, minor: 12),
        .Package(url: "https://github.com/jdhealy/PrettyColors.git", majorVersion: 5),
        .Package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", majorVersion: 1, minor: 1),
        .Package(url: "https://github.com/mdiep/Tentacle.git", majorVersion: 0, minor: 7),
        .Package(url: "https://github.com/thoughtbot/Argo.git", majorVersion: 4, minor: 1),
        .Package(url: "https://github.com/thoughtbot/Runes.git", versions: Version(4, 0, 1)..<Version(4, .max, .max)),
    ],
    exclude: [
        "Source/CarthageIntegration",
        "Source/Scripts",
        "Source/carthage/swift-is-crashy.c",
        "Tests/CarthageKitTests/Resources/FakeOldObjc.framework",
    ]
)
