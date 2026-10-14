// swift-tools-version: 5.9
import PackageDescription

// PulseStrengthKit
//
// The strength-workout feature for Pulse: platform-neutral core (models, reducer,
// presenter, persistence, sync) plus the iOS UI, the Live Activity attributes / command
// bus and the Apple Watch UI. The Lock Screen / Dynamic Island views and the App Intents
// are source files shared by the app and widget extension (Apps/Shared), see the README. See ../../ARCHITECTURE.md.
//
// Only PulseStrengthCore is buildable and testable off Apple platforms (Linux CI).
// Every other target wraps its sources in `#if os(iOS)` / `#if os(watchOS)` so the
// package still resolves and builds (to empty modules) everywhere.

let package = Package(
    name: "PulseStrengthKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "PulseStrengthCore", targets: ["PulseStrengthCore"]),
        .library(name: "PulseStrengthActivity", targets: ["PulseStrengthActivity"]),
        .library(name: "PulseStrengthIOS", targets: ["PulseStrengthIOS"]),
        .library(name: "PulseStrengthWatchUI", targets: ["PulseStrengthWatchUI"]),
    ],
    targets: [
        .target(name: "PulseStrengthCore"),
        .target(name: "PulseStrengthActivity", dependencies: ["PulseStrengthCore"]),
        .target(
            name: "PulseStrengthIOS",
            dependencies: ["PulseStrengthCore", "PulseStrengthActivity"],
            resources: [.process("Resources")]
        ),
        .target(name: "PulseStrengthWatchUI", dependencies: ["PulseStrengthCore"]),
        .testTarget(name: "PulseStrengthCoreTests", dependencies: ["PulseStrengthCore"]),
    ]
)
