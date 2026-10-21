// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MonekarCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "MonekarCore", targets: ["MonekarCore"])],
    targets: [
        .target(name: "MonekarCore", path: "Monekar/Core"),
        .testTarget(name: "MonekarCoreTests", dependencies: ["MonekarCore"], path: "MonekarTests"),
    ]
)
