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
        .package(path: "../Persistence"),
        .package(path: "../Categorization"),
    ],
    targets: [
        .target(
            name: "Importing",
            dependencies: ["Domain", "Persistence", "Categorization"]
        ),
        .testTarget(
            name: "ImportingTests",
            dependencies: ["Importing"]
        ),
    ]
)
