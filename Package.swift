// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftWorkflow",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Workflow",
            targets: ["Workflow"]),
        .executable(
            name: "StepsFromLog",
            targets: ["StepsFromLog"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/stefanspringer1/SwiftUtilities", from: "6.0.0"),
        //.package(path: "../SwiftUtilities"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Workflow",
            dependencies: [
                .product(name: "Utilities", package: "SwiftUtilities")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ConciseMagicFile"),
            ]
        ),
        .testTarget(
            name: "WorkflowTests",
            dependencies: ["Workflow"]
        ),
        .executableTarget(
            name: "StepsFromLog",
            path: "Sources/StepsFromLog",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
    ]
)
