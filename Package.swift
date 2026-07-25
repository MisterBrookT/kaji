// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kaji",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Kaji", targets: ["Kaji"]),
        .executable(name: "KajiSleepHelper", targets: ["KajiSleepHelper"]),
        .library(name: "KajiCore", targets: ["KajiCore"])
    ],
    targets: [
        // Pure logic shared by the app and tests (no AppKit).
        .target(
            name: "KajiCore",
            path: "Sources/KajiCore"
        ),
        .executableTarget(
            name: "Kaji",
            dependencies: ["KajiCore", "KajiSleepSupport"],
            path: "Sources/Kaji"
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
            dependencies: ["KajiCore"],
            path: "Tests/KajiTests"
        )
    ]
)
