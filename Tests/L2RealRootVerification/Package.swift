// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "L2RealRootVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "L0", path: "Sources/L0", exclude: ["DESIGN.md"]),
    .target(name: "L1", dependencies: ["L0"], path: "Sources/L1", exclude: ["DESIGN.md"],
        swiftSettings: [.define("L1_ISOLATED_VERIFICATION")]),
    .target(name: "DI0", dependencies: ["L0"], path: "Sources/DI0", exclude: ["DESIGN.md"],
        swiftSettings: [.define("EXACT_DOMAIN_ISOLATED_VERIFICATION")]),
    .target(name: "L2", dependencies: ["L0", "L1", "DI0"], path: "Sources/L2", exclude: ["DESIGN.md"],
        swiftSettings: [.define("L2_ISOLATED_VERIFICATION")]),
    .target(name: "L2Fixtures", dependencies: ["L0", "L1", "L2"], path: "Sources/Fixtures"),
    .executableTarget(name: "L2Proof", dependencies: ["L2Fixtures"], path: "Sources/Proof"),
    .testTarget(name: "L2Tests", dependencies: ["L2Fixtures"], path: "Tests")
])
