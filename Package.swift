// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftCAD",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1),
        .custom("wasi", versionString: "0")
    ],
    products: [
        .library(
            name: "SwiftCAD",
            targets: ["SwiftCAD"]
        ),
        .library(
            name: "CADIR",
            targets: ["CADIR"]
        ),
        .library(
            name: "CADModeling",
            targets: ["CADModeling"]
        ),
        .library(
            name: "CADGeometry",
            targets: ["CADGeometry"]
        ),
        .library(
            name: "CADTopology",
            targets: ["CADTopology"]
        ),
        .library(
            name: "CADKernel",
            targets: ["CADKernel"]
        ),
        .library(
            name: "CADExchange",
            targets: ["CADExchange"]
        ),
        .library(
            name: "CADUSD",
            targets: ["CADUSD"]
        ),
        .executable(
            name: "CADWASMSmoke",
            targets: ["CADWASMSmoke"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/swift-OpenUSD.git",
            revision: "2c943c75ef9c0c32974663b13441a0972bec7d3e"
        ),
        .package(
            url: "https://github.com/apple/swift-collections",
            exact: "1.5.1"
        ),
    ],
    targets: [
        .target(
            name: "CADCore",
            dependencies: [
                .product(name: "HashTreeCollections", package: "swift-collections"),
            ]
        ),
        .target(
            name: "CADGeometry",
            dependencies: ["CADCore"]
        ),
        .target(
            name: "CADTopology",
            dependencies: ["CADCore", "CADGeometry"]
        ),
        .target(
            name: "CADIR",
            dependencies: ["CADCore", "CADGeometry", "CADTopology"]
        ),
        .target(
            name: "CADModeling",
            dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR"]
        ),
        .target(
            name: "CADKernel",
            dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADModeling"]
        ),
        .target(
            name: "CADUSD",
            dependencies: [
                "CADCore",
                "CADIR",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
            ]
        ),
        .target(
            name: "CADExchange",
            dependencies: [
                "CADCore",
                "CADGeometry",
                "CADIR",
                "CADTopology",
                "CADKernel",
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .product(name: "OpenUSDC", package: "swift-OpenUSD"),
                .product(name: "OpenUSDZ", package: "swift-OpenUSD"),
            ],
        ),
        .target(
            name: "SwiftCAD",
            dependencies: ["CADCore", "CADTopology", "CADIR", "CADModeling", "CADKernel", "CADExchange"]
        ),
        .executableTarget(
            name: "CADWASMSmoke",
            dependencies: ["CADCore", "CADTopology", "CADIR", "CADKernel"],
            linkerSettings: [
                .unsafeFlags(
                    ["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"],
                    .when(platforms: [.custom("wasi")])
                ),
            ]
        ),
        .testTarget(
            name: "CADCoreTests",
            dependencies: ["CADCore"]
        ),
        .testTarget(
            name: "CADGeometryTests",
            dependencies: ["CADCore", "CADGeometry"]
        ),
        .testTarget(
            name: "CADGeometryCertificationTests",
            dependencies: ["CADCore", "CADGeometry"]
        ),
        .testTarget(
            name: "CADTopologyTests",
            dependencies: ["CADCore", "CADGeometry", "CADTopology"]
        ),
        .testTarget(
            name: "CADTopologyCertificationTests",
            dependencies: ["CADCore", "CADGeometry", "CADTopology"]
        ),
        .testTarget(
            name: "CADIRTests",
            dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR"]
        ),
        .testTarget(
            name: "CADModelingTests",
            dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADModeling"]
        ),
        .testTarget(
            name: "CADKernelTests",
            dependencies: ["CADCore", "CADTopology", "CADIR", "CADModeling", "CADKernel"]
        ),
        .testTarget(
            name: "CADExchangeTests",
            dependencies: ["CADCore", "CADTopology", "CADIR", "CADModeling", "CADKernel", "CADExchange"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "CADUSDImportTests",
            dependencies: [
                "CADCore",
                "CADIR",
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .product(name: "OpenUSDC", package: "swift-OpenUSD"),
                .product(name: "OpenUSDZ", package: "swift-OpenUSD"),
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "SwiftCADTests",
            dependencies: ["SwiftCAD", "CADExchange", "CADKernel", "CADModeling", "CADIR", "CADTopology", "CADCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
