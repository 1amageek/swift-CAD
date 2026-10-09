// swift-tools-version: 6.4
import PackageDescription
import Foundation
let collectionDependency: Package.Dependency = {
    if let path = ProcessInfo.processInfo.environment["CAD_COLLECTIONS_PATH"] { return .package(path: path) }
    return .package(url: "https://github.com/apple/swift-collections", exact: "1.5.1")
}()
let package = Package(name: "NativeExactRelationVerification", platforms: [.macOS(.v15), .custom("wasi", versionString: "0")], dependencies: [
 collectionDependency
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
 .target(name:"NativePrimitiveSourceFixtures",dependencies:["CADCore","CADGeometry"],path:"Sources/M3Fixtures"),
 .executableTarget(name:"NativePrimitiveSourceProof",dependencies:["NativePrimitiveSourceFixtures"],path:"Sources/M3Proof"),
 .target(name:"NativeDomainFamilyFixtures",dependencies:["CADCore","CADGeometry"],path:"Sources/FamilyFixtures",swiftSettings:[.define("NATIVE_FAMILY_FULL_VERIFICATION")]),
 .executableTarget(name:"NativeDomainFamilyProof",dependencies:["NativeDomainFamilyFixtures"],path:"Sources/FamilyProof"),
 .testTarget(name: "NativeExactTests", dependencies: ["NativeExactFixtures"], path: "Tests")
])
