// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HappySpendingCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HappySpendingCore", targets: ["HappySpendingCore"]),
    ],
    targets: [
        .target(name: "HappySpendingCore"),
        .testTarget(name: "HappySpendingCoreTests", dependencies: ["HappySpendingCore"]),
    ]
)
