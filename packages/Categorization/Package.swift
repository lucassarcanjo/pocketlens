// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Categorization",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Categorization", targets: ["Categorization"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../Persistence"),
        .package(path: "../Importing"),
        .package(path: "../LLM"),
    ],
    targets: [
        .target(
            name: "Categorization",
            dependencies: ["Domain", "Persistence", "Importing", "LLM"]
        ),
        .testTarget(
            name: "CategorizationTests",
            dependencies: ["Categorization"]
        ),
    ]
)
