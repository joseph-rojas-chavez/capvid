// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapVid",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CapVid",
            targets: ["CapVid"]
        ),
    ],
    targets: [
        .target(
            name: "CapVid"
        ),
        .testTarget(
            name: "CapVidTests",
            dependencies: ["CapVid"]
        ),
    ]
)
