// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "NativeExactRelationVerification", platforms: [.macOS(.v15), .custom("wasi", versionString: "0")], dependencies: [
 .package(path: "/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/.build/checkouts/swift-collections")
], targets: [
 .target(name: "CADCore", dependencies: [.product(name: "HashTreeCollections", package: "swift-collections")]),
 .target(name: "CADGeometry", dependencies: ["CADCore"]),
 .target(name: "NativeExactFixtures", dependencies: ["CADCore", "CADGeometry"], path: "Sources/Fixtures"),
 .executableTarget(name: "NativeExactProof", dependencies: ["NativeExactFixtures"], path: "Sources/Proof", linkerSettings: [
 .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"], .when(platforms: [.custom("wasi")]))]),
 .executableTarget(name: "NativeExactGeometricProof", dependencies: ["NativeExactFixtures"], path: "Sources/GeometricProof", linkerSettings: [
 .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"], .when(platforms: [.custom("wasi")]))]),
 .executableTarget(name: "NativeExactPreparationProof", dependencies: ["NativeExactFixtures"], path: "Sources/PreparationProof", linkerSettings: [
 .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"], .when(platforms: [.custom("wasi")]))]),
 .executableTarget(name: "CADIntersectionPortabilitySmoke", dependencies: ["CADCore", "CADGeometry"],
 linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"], .when(platforms: [.custom("wasi")]))]),
 .testTarget(name: "NativeExactTests", dependencies: ["NativeExactFixtures"], path: "Tests")
])
