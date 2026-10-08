// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "L5ParametricRelationVerification", platforms: [.macOS(.v14)], targets: [
 .target(name: "L0", path: "Sources/L0", exclude: ["DESIGN.md"]),
 .target(name: "L1", dependencies: ["L0"], path: "Sources/L1", exclude: ["DESIGN.md"], swiftSettings: [.define("L1_ISOLATED_VERIFICATION")]),
 .target(name: "DI0", dependencies: ["L0"], path: "Sources/DI0", exclude: ["DESIGN.md"], swiftSettings: [.define("EXACT_DOMAIN_ISOLATED_VERIFICATION")]),
 .target(name: "L2", dependencies: ["L0", "L1", "DI0"], path: "Sources/L2", exclude: ["DESIGN.md"], swiftSettings: [.define("L2_ISOLATED_VERIFICATION")]),
 .target(name: "L3", dependencies: ["L0", "L1", "L2"], path: "Sources/L3", exclude: ["DESIGN.md"], swiftSettings: [.define("L3_ISOLATED_VERIFICATION")]),
 .target(name: "L4", dependencies: ["L0", "L1", "L2", "L3"], path: "Sources/L4", exclude: ["DESIGN.md"], swiftSettings: [.define("L4_ISOLATED_VERIFICATION")]),
 .target(name: "L5", dependencies: ["L0", "L1", "L2", "L3", "L4"], path: "Sources/L5", exclude: ["DESIGN.md"], swiftSettings: [.define("L5_ISOLATED_VERIFICATION")]),
 .target(name: "L5Fixtures", dependencies: ["L0", "L1", "L2", "L3", "L4", "L5"], path: "Sources/Fixtures"),
 .executableTarget(name: "L5Proof", dependencies: ["L5Fixtures"], path: "Sources/Proof"),
 .testTarget(name: "L5Tests", dependencies: ["L5Fixtures"], path: "Tests")
])
