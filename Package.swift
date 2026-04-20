// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CreatorRecorder",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CreatorRecorderKit",
            targets: ["CreatorRecorderKit"]
        ),
        .executable(
            name: "CreatorRecorder",
            targets: ["CreatorRecorder"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "CreatorRecorderKit"
        ),
        .executableTarget(
            name: "CreatorRecorder",
            dependencies: ["CreatorRecorderKit"]
        ),
        .testTarget(
            name: "CreatorRecorderTests",
            dependencies: [
                "CreatorRecorderKit",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
