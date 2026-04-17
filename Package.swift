// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aether",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .executable(name: "AetherApp", targets: ["AetherApp"]),
        .library(name: "AetherCore", targets: ["AetherCore"]),
        .library(name: "AetherUI", targets: ["AetherUI"]),
    ],
    targets: [
        // Shared library — models, services, storage (all platforms)
        .target(
            name: "AetherCore",
            path: "Sources/AetherCore"
        ),
        // Shared UI components (macOS, iOS, tvOS)
        .target(
            name: "AetherUI",
            dependencies: ["AetherCore"],
            path: "Sources/AetherUI"
        ),
        // macOS app — @main entry point via SwiftUI App protocol
        .executableTarget(
            name: "AetherApp",
            dependencies: ["AetherCore", "AetherUI"],
            path: "Sources/AetherApp",
            resources: [
                .process("Resources/Assets.xcassets"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        // iOS app target
        .target(
            name: "AetherAppIOS",
            dependencies: ["AetherCore", "AetherUI"],
            path: "Sources/AetherAppIOS",
            resources: [.process("Resources/Assets.xcassets")]
        ),
        // tvOS app target
        .target(
            name: "AetherAppTV",
            dependencies: ["AetherCore", "AetherUI"],
            path: "Sources/AetherAppTV",
            resources: [.process("Resources/Assets.xcassets")]
        ),
        // Unit tests
        .testTarget(
            name: "AetherTests",
            dependencies: ["AetherCore"],
            path: "Sources/AetherTests"
        )
    ]
)
