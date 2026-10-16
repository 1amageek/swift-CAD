// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SwiftCAD",
  platforms: [
    .macOS("27.0"),
    .iOS("27.0"),
    .visionOS("27.0"),
    .custom("wasi", versionString: "0"),
  ],
  products: [
    .library(
      name: "CADCore",
      targets: ["CADCore"]
    ),
    .library(
      name: "SwiftCAD",
      targets: ["SwiftCAD"]
    ),
    .library(
      name: "CADIR",
      targets: ["CADIR"]
    ),
    .library(
      name: "CADCapabilities",
      targets: ["CADCapabilities"]
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
    .executable(
      name: "CADGeometryWASMSmoke",
      targets: ["CADGeometryWASMSmoke"]
    ),
    .executable(
      name: "CADContractWASMSmoke",
      targets: ["CADContractWASMSmoke"]
    ),
    .executable(
      name: "A2DocumentTransactionSmoke",
      targets: ["A2DocumentTransactionSmoke"]
    ),
    .executable(
      name: "CADIntersectionPortabilitySmoke",
      targets: ["CADIntersectionPortabilitySmoke"]
    ),
    .executable(
      name: "CADCorePortabilitySmoke",
      targets: ["CADCorePortabilitySmoke"]
    ),
  ],
  traits: [
    .trait(name: "NativeExchange", description: "Native format and package transport adapters"),
    .default(enabledTraits: ["NativeExchange"]),
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
        .product(name: "HashTreeCollections", package: "swift-collections")
      ]
    ),
    .target(
      name: "CADGeometry",
      dependencies: ["CADCore"]
    ),
    .executableTarget(
      name: "CADIntersectionPortabilitySmoke",
      dependencies: ["CADCore", "CADGeometry"],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"],
          .when(platforms: [.custom("wasi")]))
      ]
    ),
    .target(
      name: "CADCapabilities",
      dependencies: ["CADCore"]
    ),
    .target(
      name: "CADTopology",
      dependencies: ["CADCore", "CADGeometry", .product(name: "HashTreeCollections", package: "swift-collections")]
    ),
    .target(
      name: "CADIR",
      dependencies: ["CADCore", "CADGeometry", "CADTopology", .product(name: "HashTreeCollections", package: "swift-collections")]
    ),
    .target(
      name: "CADModeling",
      dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR"]
    ),
    .target(
      name: "CADKernel",
      dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADModeling", .product(name: "HashTreeCollections", package: "swift-collections")]
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
      cSettings: [
        .define("_WASI_EMULATED_SIGNAL", .when(platforms: [.custom("wasi")])),
        .define("_WASI_EMULATED_MMAN", .when(platforms: [.custom("wasi")])),
      ],
      linkerSettings: [
        .linkedLibrary("wasi-emulated-signal", .when(platforms: [.custom("wasi")])),
        .linkedLibrary("wasi-emulated-mman", .when(platforms: [.custom("wasi")])),
      ]
    ),
    .target(
      name: "SwiftCAD",
      dependencies: [
        "CADCore", "CADCapabilities", "CADGeometry", "CADTopology", "CADIR", "CADModeling", "CADKernel",
        .target(name: "CADExchange", condition: .when(traits: ["NativeExchange"])),
      ],
      cSettings: [
        .define("_WASI_EMULATED_SIGNAL", .when(platforms: [.custom("wasi")])),
        .define("_WASI_EMULATED_MMAN", .when(platforms: [.custom("wasi")])),
      ],
      swiftSettings: [
        .define("CAD_EXCHANGE", .when(traits: ["NativeExchange"])),
      ],
      linkerSettings: [
        .linkedLibrary("wasi-emulated-signal", .when(platforms: [.custom("wasi")])),
        .linkedLibrary("wasi-emulated-mman", .when(platforms: [.custom("wasi")])),
      ]
    ),
    .executableTarget(
      name: "CADGeometryWASMSmoke",
      dependencies: ["CADCore", "CADGeometry", "CADIR", "CADTopology"],
      linkerSettings: [
        .unsafeFlags(
          ["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"],
          .when(platforms: [.custom("wasi")])
        )
      ]
    ),
    .executableTarget(
      name: "CADContractWASMSmoke",
      dependencies: ["CADCore", "CADCapabilities"]
    ),
    .executableTarget(
      name: "CADWASMSmoke",
      dependencies: ["CADCore", "CADGeometry", "CADTopology", "CADIR", "CADKernel", "CADCapabilities"],
      linkerSettings: [
        .unsafeFlags(
          ["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"],
          .when(platforms: [.custom("wasi")])
        )
      ]
    ),
    .executableTarget(
      name: "A2DocumentTransactionSmoke",
      dependencies: ["SwiftCAD"],
      cSettings: [
        .define("_WASI_EMULATED_SIGNAL", .when(platforms: [.custom("wasi")])),
        .define("_WASI_EMULATED_MMAN", .when(platforms: [.custom("wasi")])),
      ],
      linkerSettings: [
        .linkedLibrary("wasi-emulated-signal", .when(platforms: [.custom("wasi")])),
        .linkedLibrary("wasi-emulated-mman", .when(platforms: [.custom("wasi")])),
        .unsafeFlags(
          ["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"],
          .when(platforms: [.custom("wasi")])
        ),
      ]
    ),
    .executableTarget(
      name: "CADCorePortabilitySmoke",
      dependencies: [
        "CADCore",
        .product(name: "HashTreeCollections", package: "swift-collections"),
      ],
      cSettings: [
        .define("_WASI_EMULATED_SIGNAL", .when(platforms: [.custom("wasi")])),
        .define("_WASI_EMULATED_MMAN", .when(platforms: [.custom("wasi")])),
      ],
      linkerSettings: [
        .linkedLibrary("wasi-emulated-signal", .when(platforms: [.custom("wasi")])),
        .linkedLibrary("wasi-emulated-mman", .when(platforms: [.custom("wasi")])),
      ]
    ),
    .testTarget(
      name: "CADCoreTests",
      dependencies: ["CADCore"]
    ),
    .testTarget(
      name: "CADCapabilitiesTests",
      dependencies: ["CADCore", "CADCapabilities", "CADIR"]
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
        .copy("Fixtures")
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
        .copy("Fixtures")
      ]
    ),
    .testTarget(
      name: "SwiftCADTests",
      dependencies: [
        "SwiftCAD", "CADCapabilities", "CADExchange", "CADKernel", "CADModeling", "CADIR",
        "CADTopology", "CADCore",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
