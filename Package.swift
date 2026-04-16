// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aether",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AetherApp", targets: ["AetherApp"]),
        .library(name: "AetherCore", targets: ["AetherCore"]),
    ],
    targets: [
        // Shared library — models, services, storage (all platforms)
        .target(
            name: "AetherCore",
            path: "Sources/AetherCore"
        ),
        // macOS app — @main entry point via SwiftUI App protocol
        .executableTarget(
            name: "AetherApp",
            dependencies: ["AetherCore"],
            path: "Sources/AetherApp",
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Info.plist"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        // Unit tests
        .testTarget(
            name: "AetherTests",
            dependencies: ["AetherCore"],
            path: "Sources/AetherTests"
        )
    ]
)
