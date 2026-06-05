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
            name: "USDCImport",
            description: "Enable the pure Swift USDC reader."
        ),
        .trait(
            name: "USDZImport",
            description: "Enable the pure Swift USDZ reader."
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
            ]
        ),
        .target(
            name: "CADUSDZ",
            dependencies: [
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .product(name: "OpenUSDZ", package: "swift-OpenUSD"),
            ]
        ),
        .target(
            name: "CADExchange",
            dependencies: [
                "CADCore",
                "CADIR",
                "CADKernel",
                "CADUSD",
                .product(name: "OpenUSD", package: "swift-OpenUSD"),
                .target(name: "CADUSDC", condition: .when(traits: ["USDCImport"])),
                .target(name: "CADUSDZ", condition: .when(traits: ["USDZImport"])),
            ],
            swiftSettings: [
                .define("CAD_ENABLE_USDC_READER", .when(traits: ["USDCImport"])),
                .define("CAD_ENABLE_USDZ_READER", .when(traits: ["USDZImport"])),
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
            swiftSettings: [
                .define("CAD_ENABLE_USDC_READER", .when(traits: ["USDCImport"])),
                .define("CAD_ENABLE_USDZ_READER", .when(traits: ["USDZImport"])),
            ]
        ),
        .testTarget(
            name: "SwiftCADTests",
            dependencies: ["SwiftCAD", "CADExchange", "CADKernel", "CADIR", "CADCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
