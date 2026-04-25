// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LLM", targets: ["LLM"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "LLM",
            dependencies: ["Domain"]
        ),
        .testTarget(
            name: "LLMTests",
            dependencies: ["LLM"]
        ),
    ]
)
