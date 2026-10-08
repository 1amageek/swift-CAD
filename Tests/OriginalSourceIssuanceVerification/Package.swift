// swift-tools-version: 6.4
import PackageDescription

// Verification-only graph; no upper geometry target or external dependency.
let package = Package(name: "OriginalSourceIssuanceVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "L0", path: "Sources/L0", exclude: ["DESIGN.md"]),
    .target(name: "L1", dependencies: ["L0"], path: "Sources/L1", exclude: ["DESIGN.md"],
        swiftSettings: [.define("L1_ISOLATED_VERIFICATION")]),
    .target(name: "SourceIssuer", dependencies: ["L0", "L1"], path: "Sources/SourceIssuer", exclude: ["DESIGN.md"],
        swiftSettings: [.define("ORIGINAL_SOURCE_ISOLATED_VERIFICATION")]),
    .target(name: "SourceIssuerFixtures", dependencies: ["L0", "L1", "SourceIssuer"], path: "Sources/Fixtures"),
    .executableTarget(name: "SourceIssuerProof", dependencies: ["SourceIssuerFixtures"], path: "Sources/Proof"),
    .testTarget(name: "SourceIssuerTests", dependencies: ["SourceIssuerFixtures"], path: "Tests")
])
