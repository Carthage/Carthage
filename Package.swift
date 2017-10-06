// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Carthage",
    products: [
        .library(name: "XCDBLD", targets: ["XCDBLD"]),
        .library(name: "CarthageKit", targets: ["CarthageKit"]),
        .executable(name: "carthage", targets: ["carthage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/antitypical/Result.git", from: "3.2.1"),
        .package(url: "https://github.com/Carthage/ReactiveTask.git", from: "0.13.0"),
        .package(url: "https://github.com/Carthage/Commandant.git", from: "0.12.0"),
        .package(url: "https://github.com/jdhealy/PrettyColors.git", from: "5.0.0"),
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "2.0.0"),
        .package(url: "https://github.com/mdiep/Tentacle.git", from: "0.9.0"),
        .package(url: "https://github.com/thoughtbot/Argo.git", from: "4.1.0"),
        .package(url: "https://github.com/thoughtbot/Curry.git", from: "3.0.0"),
        .package(url: "https://github.com/thoughtbot/Runes.git", from: "4.0.1"),
        .package(url: "https://github.com/Quick/Quick.git", from: "1.2.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "7.0.2"),
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
            dependencies: ["XCDBLD", "Tentacle", "Argo", "Curry", "Runes"]
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
    swiftLanguageVersions: [4]
)
