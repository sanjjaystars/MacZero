// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacZero",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacZeroCore",
            targets: ["MacZeroCore"]
        ),
        .executable(
            name: "MacZeroApp",
            targets: ["MacZeroApp"]
        ),
        .executable(
            name: "maczero",
            targets: ["MacZeroCLI"]
        ),
        .executable(
            name: "maczero-tests",
            targets: ["MacZeroTests"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacZeroCore",
            dependencies: [],
            path: "Sources/MacZeroCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacZeroApp",
            dependencies: ["MacZeroCore"],
            path: "Sources/MacZeroApp"
        ),
        .executableTarget(
            name: "MacZeroCLI",
            dependencies: ["MacZeroCore"],
            path: "Sources/MacZeroCLI"
        ),
        .executableTarget(
            name: "MacZeroTests",
            dependencies: ["MacZeroCore"],
            path: "Tests/MacZeroTests"
        )
    ]
)
