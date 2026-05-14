// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CIMetalCompilerPlugin",
    products: [
        .plugin(name: "CIMetalCompilerPlugin", targets: ["CIMetalCompilerPlugin"]),
        .executable(name: "CIMetalCompilerTool", targets: ["CIMetalCompilerTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    ],
    targets: [
        .plugin(name: "CIMetalCompilerPlugin", capability: .buildTool(), dependencies: ["CIMetalCompilerTool"]),
        .executableTarget(name: "CIMetalCompilerTool", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(
            name: "CIMetalCompilerPluginTests",
            dependencies: [],
            exclude: ["Shaders/"],
            plugins: ["CIMetalCompilerPlugin"]
        )
    ]
)
