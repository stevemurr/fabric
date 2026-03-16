// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fabric",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Fabric",
            targets: ["Fabric"]
        ),
        .library(
            name: "FabricGateway",
            targets: ["FabricGateway"]
        ),
        .library(
            name: "FabricShowcaseSupport",
            targets: ["FabricShowcaseSupport"]
        ),
        .executable(
            name: "FabricBrokerRuntime",
            targets: ["FabricBrokerRuntime"]
        ),
        .executable(
            name: "FabricShowcase",
            targets: ["FabricShowcase"]
        ),
    ],
    targets: [
        .target(
            name: "Fabric"
        ),
        .target(
            name: "FabricGateway",
            dependencies: ["Fabric"]
        ),
        .target(
            name: "FabricShowcaseSupport",
            dependencies: ["Fabric"]
        ),
        .executableTarget(
            name: "FabricBrokerRuntime",
            dependencies: ["Fabric", "FabricGateway"]
        ),
        .executableTarget(
            name: "FabricShowcase",
            dependencies: ["Fabric", "FabricGateway", "FabricShowcaseSupport"]
        ),
        .testTarget(
            name: "FabricTests",
            dependencies: ["Fabric", "FabricGateway", "FabricShowcaseSupport"]
        ),
    ]
)
