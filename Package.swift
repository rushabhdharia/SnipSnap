// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnipSnap",
    platforms: [.macOS(.v14)],
    targets: [
        // All app logic lives here so it can be exercised without launching
        // the GUI. Built with testing enabled in debug, so the check runner
        // below can reach internals via `@testable import`.
        .target(
            name: "SnipSnapCore",
            path: "Sources/SnipSnapCore",
            // Keep `@testable import` working in release too, so the
            // SnipSnapChecks runner builds under any configuration.
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .release))]
        ),
        // The actual app: a thin shell around SnipSnapCore.
        .executableTarget(
            name: "SnipSnap",
            dependencies: ["SnipSnapCore"],
            path: "Sources/SnipSnap"
        ),
        // `swift run SnipSnapChecks` — a dependency-free test runner that
        // works under the Command Line Tools toolchain (no Xcode / XCTest).
        .executableTarget(
            name: "SnipSnapChecks",
            dependencies: ["SnipSnapCore"],
            path: "Sources/SnipSnapChecks"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
