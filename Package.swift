// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Reco",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RecoKit",
            targets: ["RecoKit"]
        ),
        .executable(
            name: "Reco",
            targets: ["Reco"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "RecoKit"
        ),
        .executableTarget(
            name: "Reco",
            dependencies: ["RecoKit"],
            exclude: ["Info.plist", "Resources"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Reco/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "RecoTests",
            dependencies: [
                "RecoKit",
                "Reco",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
