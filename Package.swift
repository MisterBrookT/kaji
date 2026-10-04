// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kaji",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Kaji", targets: ["Kaji"]),
        .executable(name: "kaji-cli", targets: ["KajiCommand"]),
        .executable(name: "KajiSleepHelper", targets: ["KajiSleepHelper"]),
        .library(name: "KajiCore", targets: ["KajiCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        // Pure logic shared by the app and tests (no AppKit).
        .target(
            name: "KajiCore",
            path: "Sources/KajiCore"
        ),
        .executableTarget(
            name: "Kaji",
            dependencies: [
                "KajiCore",
                "KajiSleepSupport",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Kaji",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(
            name: "KajiCommand",
            path: "Sources/KajiCLI"
        ),
        .target(
            name: "KajiSleepSupport",
            path: "Sources/KajiSleepSupport"
        ),
        .executableTarget(
            name: "KajiSleepHelper",
            dependencies: ["KajiSleepSupport"],
            path: "Sources/KajiSleepHelper"
        ),
        .testTarget(
            name: "KajiTests",
            dependencies: ["KajiCore", "Kaji"],
            path: "Tests/KajiTests"
        )
    ]
)
