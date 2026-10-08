// swift-tools-version: 6.4
import PackageDescription

// Verification only: the production module is unchanged.
let package = Package(name: "OriginalDomainIdentityVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "L0", path: "Sources/L0", exclude: ["DESIGN.md"]),
    .target(name: "DI0", dependencies: ["L0"], path: "Sources/DI0", exclude: ["DESIGN.md"],
        swiftSettings: [.define("EXACT_DOMAIN_ISOLATED_VERIFICATION")]),
    .executableTarget(name: "DomainDependencyProbe", dependencies: ["L0", "DI0"], path: "Sources/Probe"),
    .target(name: "DomainFixtures", dependencies: ["L0", "DI0"], path: "Sources/Fixtures"),
    .executableTarget(name: "DomainProof", dependencies: ["DomainFixtures"], path: "Sources/Proof"),
    .testTarget(name: "DomainTests", dependencies: ["DomainFixtures"], path: "Tests")
])
