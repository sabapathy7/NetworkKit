// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "NetworkKit",
            targets: ["NetworkKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sabapathy7/NetworkKitCore.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "NetworkKit",
            dependencies: [
                .product(name: "NetworkKitCore", package: "NetworkKitCore")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "NetworkKitTests",
            dependencies: ["NetworkKit", .product(name: "NetworkKitCore", package: "NetworkKitCore")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "NetworkKit_SwiftTest",
            dependencies: ["NetworkKit", .product(name: "NetworkKitCore", package: "NetworkKitCore")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ])
    ]
)
