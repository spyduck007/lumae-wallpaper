// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LumaeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LumaeCore", targets: ["LumaeCore"])
    ],
    targets: [
        .target(
            name: "LumaeCore",
            path: "Sources/LumaeCore"
        ),
        .testTarget(
            name: "LumaeCoreTests",
            dependencies: ["LumaeCore"],
            path: "Tests/LumaeCoreTests"
        )
    ]
)
