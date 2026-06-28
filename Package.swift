// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TinyStats",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "SMCKit",
            dependencies: ["CSMC"]
        ),
        // Dependency-free XPC contract shared by the app and the privileged fan helper.
        .target(
            name: "FanControlShared"
        ),
        // Exposes <notify.h> (Darwin notifications) to Swift, for observing macOS Game Mode.
        .target(
            name: "CGameMode"
        ),
        .target(
            name: "TinyStatsCore",
            dependencies: ["SMCKit", "FanControlShared"]
        ),
        // Root daemon that performs the privileged SMC fan writes (installed as a LaunchDaemon).
        .executableTarget(
            name: "TinyStatsFanHelper",
            dependencies: ["SMCKit", "FanControlShared"]
        ),
        .executableTarget(
            name: "TinyStats",
            dependencies: ["TinyStatsCore", "SMCKit", "FanControlShared", "CGameMode"],
            resources: [.process("Resources")]
        ),
        // Self-test runner: works with Command Line Tools only (no Xcode / XCTest needed).
        // Run with `swift run TinyStatsSelfTest`.
        .executableTarget(
            name: "TinyStatsSelfTest",
            dependencies: ["TinyStatsCore"]
        ),
    ]
)
