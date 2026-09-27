// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGame",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacGameCore",
            targets: ["MacGameCore"]
        ),
        .executable(
            name: "MacGameApp",
            targets: ["MacGameApp"]
        ),
        .executable(
            name: "macgame",
            targets: ["MacGameCLI"]
        ),
        .executable(
            name: "macgame-tests",
            targets: ["MacGameTests"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacGameCore",
            dependencies: [],
            path: "Sources/MacGameCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacGameApp",
            dependencies: ["MacGameCore"],
            path: "Sources/MacGameApp"
        ),
        .executableTarget(
            name: "MacGameCLI",
            dependencies: ["MacGameCore"],
            path: "Sources/MacGameCLI"
        ),
        .executableTarget(
            name: "MacGameTests",
            dependencies: ["MacGameCore"],
            path: "Tests/MacGameTests"
        )
    ]
)
