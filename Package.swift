// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Carthage",
    products: [
        .library(name: "XCDBLD", targets: ["XCDBLD"]),
        .library(name: "CarthageKit", targets: ["CarthageKit"]),
        .executable(name: "carthage", targets: ["carthage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/antitypical/Result.git", from: "4.1.0"),
        .package(url: "https://github.com/Carthage/ReactiveTask.git", from: "0.16.0"),
        .package(url: "https://github.com/Carthage/Commandant.git", from: "0.16.0"),
        .package(url: "https://github.com/jdhealy/PrettyColors.git", from: "5.0.2"),
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "5.0.0"),
        .package(url: "https://github.com/mdiep/Tentacle.git", from: "0.13.1"),
        .package(url: "https://github.com/thoughtbot/Curry.git", from: "4.0.2"),
        .package(url: "https://github.com/Quick/Quick.git", from: "2.2.1"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "8.0.9"),
    ],
    targets: [
        .target(
            name: "XCDBLD",
            dependencies: ["Result", "ReactiveSwift", "ReactiveTask"]
        ),
        .testTarget(
            name: "XCDBLDTests",
            dependencies: ["XCDBLD", "Quick", "Nimble"]
        ),
        .target(
            name: "CarthageKit", 
            dependencies: ["XCDBLD", "Tentacle", "Curry"]
        ),
        .testTarget(
            name: "CarthageKitTests",
            dependencies: ["CarthageKit", "Quick", "Nimble"],
            exclude: ["Resources/FakeOldObjc.framework"]
        ),
        .target(
            name: "carthage",
            dependencies: ["XCDBLD", "CarthageKit", "Commandant", "Curry", "PrettyColors"],
            exclude: ["swift-is-crashy.c"]
        ),
    ],
    swiftLanguageVersions: [.v4_2]
)
