// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CloudKitSync",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "CloudKitSync", targets: ["CloudKitSync"]),
    ],
    targets: [
        .target(name: "CloudKitSync"),
        .testTarget(name: "CloudKitSyncTests", dependencies: ["CloudKitSync"]),
    ]
)
