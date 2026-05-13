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
    targets: [
        .target(
            name: "NetworkKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "NetworkKitTests",
            dependencies: ["NetworkKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ])
    ]
)
