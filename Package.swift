// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kaji",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Kaji", targets: ["Kaji"]),
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
            dependencies: ["KajiCore"],
            path: "Sources/Kaji"
        ),
        .testTarget(
            name: "KajiTests",
            dependencies: ["KajiCore"],
            path: "Tests/KajiTests"
        )
    ]
)
