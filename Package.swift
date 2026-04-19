// swift-tools-version: 6.0
import PackageDescription

let swiftV5: [SwiftSetting] = [
    .swiftLanguageMode(.v5)  // disable Swift 6 strict concurrency during dev
]

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
            path: "Sources/AetherCore",
            swiftSettings: swiftV5
        ),
        // Shared SwiftUI components — all platforms
        .target(
            name: "AetherUI",
            dependencies: ["AetherCore"],
            path: "Sources/AetherUI",
            swiftSettings: swiftV5
        ),
        // macOS app — @main entry point via SwiftUI App protocol
        .executableTarget(
            name: "AetherApp",
            dependencies: ["AetherCore", "AetherUI"],
            path: "Sources/AetherApp",
            resources: [
                .process("Resources/Assets.xcassets"),
            ],
            swiftSettings: swiftV5 + [
                .unsafeFlags(["-parse-as-library"]),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "/Users/friendlygiver1337/aether/Sources/AetherApp/Info.plist"
                ], .when(platforms: [.macOS]))
            ]
        ),
        // iOS app target — library (entry point via Xcode scheme, not SPM executable)
        .target(
            name: "AetherAppIOS",
            dependencies: ["AetherCore", "AetherUI"],
            path: "Sources/AetherAppIOS",
            swiftSettings: swiftV5
        ),
        // tvOS app target — library (entry point via Xcode scheme, not SPM executable)
        .target(
            name: "AetherAppTV",
            dependencies: ["AetherCore", "AetherUI"],
            path: "Sources/AetherAppTV",
            swiftSettings: swiftV5
        ),
        // Unit tests
        .testTarget(
            name: "AetherTests",
            dependencies: ["AetherCore"],
            path: "Sources/AetherTests",
            swiftSettings: swiftV5
        )
    ]
)
