// swift-tools-version: 6.2
import PackageDescription

// Sparkle (auto-update) is a macOS-only, app-target-only dependency. Core and the
// CLI stay portable so they build and test on Linux CI without an app bundle.
let package = Package(
    name: "Clockwork",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ClockworkCore", targets: ["ClockworkCore"]),
        .executable(name: "clockworkcli", targets: ["clockworkcli"]),
        .executable(name: "Clockwork", targets: ["Clockwork"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ],
    targets: [
        // Portable domain logic. No AppKit/SwiftUI — compiles on Linux.
        .target(
            name: "ClockworkCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // Headless proof that Core is usable without an app bundle: prints state as JSON.
        .executableTarget(
            name: "clockworkcli",
            dependencies: ["ClockworkCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // The macOS menu bar app. Sparkle is linked here only.
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
        // macOS unit tests over Core (Swift Testing).
        .testTarget(
            name: "ClockworkCoreTests",
            dependencies: ["ClockworkCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
        // The portable subset that also runs on Linux CI.
        .testTarget(
            name: "ClockworkCoreLinuxTests",
            dependencies: ["ClockworkCore"],
            path: "Tests/ClockworkCoreLinuxTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ])
