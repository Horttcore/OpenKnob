// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BuzzerMac",
    products: [
        .executable(name: "BuzzerMac", targets: ["BuzzerMac"]),
        .library(name: "BuzzerCore", targets: ["BuzzerCore"]),
    ],
    targets: [
        .target(name: "BuzzerCore"),
        .executableTarget(
            name: "BuzzerMac",
            dependencies: ["BuzzerCore"]
        ),
        .testTarget(
            name: "BuzzerCoreTests",
            dependencies: ["BuzzerCore"]
        ),
    ]
)
