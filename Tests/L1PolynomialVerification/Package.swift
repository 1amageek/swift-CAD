// swift-tools-version: 6.4
import PackageDescription

let package = Package(name: "L1PolynomialVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "L0", path: "Sources/L0", exclude: ["DESIGN.md"],
        swiftSettings: [.unsafeFlags(["-enable-testing"])]),
    .target(name: "L1", dependencies: ["L0"], path: "Sources/L1", exclude: ["DESIGN.md"],
        swiftSettings: [.define("L1_ISOLATED_VERIFICATION")]),
    .target(name: "L1Fixtures", dependencies: ["L0", "L1"], path: "Sources/Fixtures"),
    .target(name: "L0Fixtures", dependencies: ["L0"], path: "Sources/L0Fixtures"),
    .executableTarget(name: "L1Proof", dependencies: ["L1Fixtures", "L0Fixtures"], path: "Sources/Proof"),
    .executableTarget(name: "L1ZeroProductBenchmark", dependencies: ["L0", "L1"], path: "Sources/Benchmark"),
    .testTarget(name: "L1PolynomialTests", dependencies: ["L0", "L1", "L1Fixtures"], path: "Tests")
])
