// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HarnessflowCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HarnessflowCore",
            targets: ["HarnessflowCore"]
        ),
    ],
    targets: [
        .target(
            name: "HarnessflowCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "HarnessflowCoreTests",
            dependencies: ["HarnessflowCore"]
        ),
    ]
)
