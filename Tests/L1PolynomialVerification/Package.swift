// swift-tools-version: 6.4
import PackageDescription

let package = Package(name: "L1PolynomialVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "L0", path: "Sources/L0", exclude: ["DESIGN.md"]),
    .target(name: "L1", dependencies: ["L0"], path: "Sources/L1", exclude: ["DESIGN.md"],
        swiftSettings: [.define("L1_ISOLATED_VERIFICATION")]),
    .target(name: "L1Fixtures", dependencies: ["L0", "L1"], path: "Sources/Fixtures"),
    .executableTarget(name: "L1Proof", dependencies: ["L1Fixtures"], path: "Sources/Proof"),
    .testTarget(name: "L1PolynomialTests", dependencies: ["L0", "L1", "L1Fixtures"], path: "Tests")
])
