// swift-tools-version: 6.4
import PackageDescription

// This is a verification-only graph. It builds only the linked L0 production sources.
let package = Package(
    name: "L0ScalarVerification",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "L0", path: "Sources/ExactScalar", exclude: ["DESIGN.md"]),
        .target(name: "L0Fixtures", dependencies: ["L0"], path: "Sources/Fixtures"),
        .executableTarget(name: "L0Proof", dependencies: ["L0Fixtures"], path: "Sources/Proof"),
        .testTarget(name: "L0ScalarTests", dependencies: ["L0", "L0Fixtures"], path: "Tests")
    ]
)
