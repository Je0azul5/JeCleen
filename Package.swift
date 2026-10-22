// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanUP",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CleanUP", targets: ["CleanUP"])],
    targets: [
        .target(name: "CleanCore"),
        .executableTarget(name: "CleanUP", dependencies: ["CleanCore"]),
        .testTarget(name: "CleanCoreTests", dependencies: ["CleanCore"])
    ]
)
