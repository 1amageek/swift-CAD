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
            name: "CADGeometry",
            targets: ["CADGeometry"]
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
        .library(
            name: "CADUSDC",
            targets: ["CADUSDC"]
        ),
        .library(
            name: "CADUSDZ",
            targets: ["CADUSDZ"]
        ),
    ],
    traits: [
        .trait(
            name: "BinaryUSDImport",
            description: "Enable binary USD import through the pure Swift USDC reader."
        ),
        .trait(
            name: "USDZPackageImport",
            description: "Enable USDZ package import through the pure Swift USDZ reader."
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/swift-OpenUSD.git",
            revision: "998e5051493adeaa138103cfcb0b17680ef0f7fe"
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
            name: "CADIR",
            dependencies: ["CADCore"]
        ),
        .target(
            name: "CADKernel",
            dependencies: ["CADCore", "CADIR", "CADGeometry"]
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
            name: "CADUSDC",
            dependencies: [
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .product(name: "OpenUSDC", package: "swift-OpenUSD"),
            ],
            path: "Sources/CADUSDC"
        ),
        .target(
            name: "CADUSDZ",
            dependencies: [
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .product(name: "OpenUSDZ", package: "swift-OpenUSD"),
            ],
            path: "Sources/CADUSDZ"
        ),
        .target(
            name: "CADExchange",
            dependencies: [
                "CADCore",
                "CADIR",
                "CADKernel",
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .target(name: "CADUSDC", condition: .when(traits: ["BinaryUSDImport"])),
                .target(name: "CADUSDZ", condition: .when(traits: ["USDZPackageImport"])),
            ],
            swiftSettings: [
                .define("CAD_ENABLE_BINARY_USD_IMPORT", .when(traits: ["BinaryUSDImport"])),
                .define("CAD_ENABLE_USDZ_PACKAGE_IMPORT", .when(traits: ["USDZPackageImport"])),
            ]
        ),
        .target(
            name: "SwiftCAD",
            dependencies: ["CADCore", "CADIR", "CADKernel", "CADExchange"]
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
            name: "CADIRTests",
            dependencies: ["CADCore", "CADIR"]
        ),
        .testTarget(
            name: "CADKernelTests",
            dependencies: ["CADCore", "CADIR", "CADKernel"]
        ),
        .testTarget(
            name: "CADExchangeTests",
            dependencies: ["CADCore", "CADIR", "CADKernel", "CADExchange"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .define("CAD_ENABLE_BINARY_USD_IMPORT", .when(traits: ["BinaryUSDImport"])),
                .define("CAD_ENABLE_USDZ_PACKAGE_IMPORT", .when(traits: ["USDZPackageImport"])),
            ]
        ),
        .testTarget(
            name: "CADUSDImportTests",
            dependencies: ["CADCore", "CADIR", "CADUSD", "CADUSDC", "CADUSDZ"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "SwiftCADTests",
            dependencies: ["SwiftCAD", "CADExchange", "CADKernel", "CADIR", "CADCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
