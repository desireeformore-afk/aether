// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aether",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared library — models, services, storage (all platforms)
        .target(
            name: "AetherCore",
            path: "Sources/AetherCore"
        ),
        // macOS app
        .executableTarget(
            name: "AetherApp",
            dependencies: ["AetherCore"],
            path: "Sources/AetherApp"
        ),
        // Unit tests
        .testTarget(
            name: "AetherTests",
            dependencies: ["AetherCore"],
            path: "Sources/AetherTests"
        )
    ]
)
