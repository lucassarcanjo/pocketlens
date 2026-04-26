// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
        .package(path: "../Importing"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                "Importing",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        ),
    ]
)
