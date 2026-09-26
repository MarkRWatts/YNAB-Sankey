// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YNABSankey",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "YNABSankey", path: "Sources/YNABSankey"),
        .testTarget(name: "YNABSankeyTests", dependencies: ["YNABSankey"], path: "Tests/YNABSankeyTests"),
    ]
)
