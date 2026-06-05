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
            name: "CADUSDCImport",
            targets: ["CADUSDCImport"]
        ),
        .library(
            name: "CADUSDZImport",
            targets: ["CADUSDZImport"]
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
        .trait(
            name: "PureSwiftUSDCImport",
            description: "Deprecated. Use BinaryUSDImport.",
            enabledTraits: ["BinaryUSDImport"]
        ),
        .trait(
            name: "PureSwiftUSDZImport",
            description: "Deprecated. Use USDZPackageImport.",
            enabledTraits: ["USDZPackageImport"]
        ),
        .trait(
            name: "USDCImport",
            description: "Deprecated. Use BinaryUSDImport.",
            enabledTraits: ["BinaryUSDImport"]
        ),
        .trait(
            name: "USDZImport",
            description: "Deprecated. Use USDZPackageImport.",
            enabledTraits: ["USDZPackageImport"]
        ),
    ],
    dependencies: [
        .package(name: "swift-OpenUSD", path: "../swift-OpenUSD"),
    ],
    targets: [
        .target(
            name: "CADCore"
        ),
        .target(
            name: "CADIR",
            dependencies: ["CADCore"]
        ),
        .target(
            name: "CADKernel",
            dependencies: ["CADCore", "CADIR"]
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
            name: "CADUSDCImport",
            dependencies: ["CADUSDC"],
            path: "Sources/CADUSDCImportCompatibility"
        ),
        .target(
            name: "CADUSDZImport",
            dependencies: ["CADUSDZ"],
            path: "Sources/CADUSDZImportCompatibility"
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
            name: "SwiftCADTests",
            dependencies: ["SwiftCAD", "CADExchange", "CADKernel", "CADIR", "CADCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
