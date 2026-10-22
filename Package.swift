// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JeCleen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JeCleen", targets: ["JeCleen"])],
    targets: [
        .target(name: "CleanCore"),
        .executableTarget(name: "JeCleen", dependencies: ["CleanCore"]),
        .testTarget(name: "CleanCoreTests", dependencies: ["CleanCore"])
    ]
)
