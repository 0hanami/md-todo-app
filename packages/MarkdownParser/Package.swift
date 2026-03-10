// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MarkdownParser",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "MarkdownParser", targets: ["MarkdownParser"]),
    ],
    targets: [
        .target(name: "MarkdownParser"),
        .testTarget(name: "MarkdownParserTests", dependencies: ["MarkdownParser"]),
    ]
)
