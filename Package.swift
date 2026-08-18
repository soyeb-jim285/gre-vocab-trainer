// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GRECore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GRECore", targets: ["GRECore"])
    ],
    targets: [
        .target(
            name: "GRECore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GRECoreTests",
            dependencies: ["GRECore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
