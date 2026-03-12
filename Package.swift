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
        .executable(
            name: "FabricBrokerRuntime",
            targets: ["FabricBrokerRuntime"]
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
        .executableTarget(
            name: "FabricBrokerRuntime",
            dependencies: ["Fabric", "FabricGateway"]
        ),
        .testTarget(
            name: "FabricTests",
            dependencies: ["Fabric", "FabricGateway"]
        ),
    ]
)
