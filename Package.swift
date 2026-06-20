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
        .target(
            name: "TinyStatsCore",
            dependencies: ["SMCKit"]
        ),
        .executableTarget(
            name: "TinyStats",
            dependencies: ["TinyStatsCore", "SMCKit"],
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
