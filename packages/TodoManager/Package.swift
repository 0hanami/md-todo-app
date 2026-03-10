// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TodoManager",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "TodoManager", targets: ["TodoManager"]),
    ],
    dependencies: [
        .package(path: "../MarkdownParser"),
        .package(path: "../CloudKitSync"),
    ],
    targets: [
        .target(
            name: "TodoManager",
            dependencies: ["MarkdownParser", "CloudKitSync"]
        ),
        .testTarget(
            name: "TodoManagerTests",
            dependencies: ["TodoManager"]
        ),
    ]
)
