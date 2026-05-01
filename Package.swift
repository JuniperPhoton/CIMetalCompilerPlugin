// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CIMetalCompilerPlugin",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .plugin(name: "CIMetalCompilerPlugin", targets: ["CIMetalCompilerPlugin"]),
        .executable(name: "CIMetalCompilerTool", targets: ["CIMetalCompilerTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", branch: "main"),
    ],
    targets: [
        .plugin(name: "CIMetalCompilerPlugin", capability: .buildTool(), dependencies: ["CIMetalCompilerTool"]),
        .executableTarget(name: "CIMetalCompilerTool", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "Subprocess", package: "swift-subprocess")
        ]),
        .testTarget(
            name: "CIMetalCompilerPluginTests",
            dependencies: [],
            exclude: ["Shaders/"],
            plugins: ["CIMetalCompilerPlugin"]
        )
    ]
)
