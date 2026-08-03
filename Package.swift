// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .library(name: "ClockworkCore", targets: ["ClockworkCore"]),
    .executable(name: "clockworkcli", targets: ["clockworkcli"]),
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    .target(
        name: "ClockworkCore",
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
        ]),
    .executableTarget(
        name: "clockworkcli",
        dependencies: ["ClockworkCore"],
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
        ]),
    .testTarget(
        name: "ClockworkCoreTests",
        dependencies: ["ClockworkCore"],
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
            .enableExperimentalFeature("SwiftTesting"),
        ]),
    .testTarget(
        name: "ClockworkCoreLinuxTests",
        dependencies: ["ClockworkCore"],
        path: "Tests/ClockworkCoreLinuxTests",
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
            .enableExperimentalFeature("SwiftTesting"),
        ]),
]

#if os(macOS)
products.append(.executable(name: "Clockwork", targets: ["Clockwork"]))
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"))
targets.insert(
    .executableTarget(
        name: "Clockwork",
        dependencies: [
            "ClockworkCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ],
        resources: [
            .process("Resources"),
        ],
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
            .define("ENABLE_SPARKLE"),
        ]),
    at: 2)
#endif

// Sparkle and the native app target only exist in the macOS manifest. Core and
// the CLI remain available to Linux builds and tests.
let package = Package(
    name: "Clockwork",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets)
