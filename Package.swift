// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AIQuery",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "AIQCore", targets: ["AIQCore"]),
        .executable(name: "aiq", targets: ["AIQuery"]),
        .executable(name: "aiq-mcp", targets: ["AIQMCP"]),
    ],
    dependencies: [
        .package(url: "git@github.com:apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "git@github.com:modelcontextprotocol/swift-sdk", from: "0.10.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "AIQuery",
            dependencies: [
                "AIQCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "AIQCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "AIQMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "AIQCoreTests",
            dependencies: [
                "AIQCore",
            ]
        )
    ]
)
