// swift-tools-version: 6.2
import PackageDescription

// Sparkle (auto-update) is a macOS-only, app-target-only dependency. Core and the
// CLI stay portable so they build and test on Linux CI without an app bundle.
let package = Package(
    name: "Scheduler",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SchedulerCore", targets: ["SchedulerCore"]),
        .executable(name: "schedulercli", targets: ["schedulercli"]),
        .executable(name: "Scheduler", targets: ["Scheduler"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ],
    targets: [
        // Portable domain logic. No AppKit/SwiftUI — compiles on Linux.
        .target(
            name: "SchedulerCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // Headless proof that Core is usable without an app bundle: prints state as JSON.
        .executableTarget(
            name: "schedulercli",
            dependencies: ["SchedulerCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // The macOS menu bar app. Sparkle is linked here only.
        .executableTarget(
            name: "Scheduler",
            dependencies: [
                "SchedulerCore",
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
            name: "SchedulerCoreTests",
            dependencies: ["SchedulerCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
        // The portable subset that also runs on Linux CI.
        .testTarget(
            name: "SchedulerCoreLinuxTests",
            dependencies: ["SchedulerCore"],
            path: "Tests/SchedulerCoreLinuxTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ])
