// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Importing",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Importing", targets: ["Importing"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../LLM"),
    ],
    targets: [
        .target(
            name: "Importing",
            dependencies: ["Domain", "LLM"]
        ),
        .testTarget(
            name: "ImportingTests",
            dependencies: ["Importing"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
