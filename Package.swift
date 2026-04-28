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
            dependencies: ["CreatorRecorderKit"],
            exclude: ["Info.plist", "Resources"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CreatorRecorder/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "CreatorRecorderTests",
            dependencies: [
                "CreatorRecorderKit",
                "CreatorRecorder",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
