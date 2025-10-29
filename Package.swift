// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NetworkKit",
            targets: ["NetworkKit"])
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NetworkKit",
            swiftSettings: [
                // Enable strict concurrency checking (Swift 6 language mode)
                .enableUpcomingFeature("StrictConcurrency"),

                // Approachable Concurrency (Swift 6.2) - single feature flag
                .enableUpcomingFeature("ApproachableConcurrency"),

                .enableExperimentalFeature("InternalImportsByDefault")
        ]),
        .testTarget(
            name: "NetworkKitTests",
            dependencies: ["NetworkKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ApproachableConcurrency")
            ])
    ]
)
