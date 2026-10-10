// swift-tools-version: 6.4
import PackageDescription
import Foundation

let dependency:Package.Dependency = {
    if let path=ProcessInfo.processInfo.environment["CAD_COLLECTIONS_PATH"] { return .package(path:path) }
    return .package(url:"https://github.com/apple/swift-collections",exact:"1.5.1")
}()
let package=Package(name:"OriginalRevolutionSourceVerification",platforms:[.macOS(.v15)],dependencies:[dependency],targets:[
    .target(name:"CADCore",dependencies:[.product(name:"HashTreeCollections",package:"swift-collections")]),
    .target(name:"CADGeometry",dependencies:["CADCore"]),
    .executableTarget(name:"OriginalRevolutionSourceProof",dependencies:["CADCore","CADGeometry"],path:"Sources/Proof"),
    .executableTarget(name:"OriginalOffsetSourceProof",dependencies:["CADCore","CADGeometry"],path:"Sources/OffsetProof"),
    .executableTarget(name:"OriginalGuideSourceProof",dependencies:["CADCore","CADGeometry"],path:"Sources/GuideProof"),
    .executableTarget(name:"OriginalBoundaryCorrectionSourceProof",dependencies:["CADCore","CADGeometry"],path:"Sources/CorrectionProof"),
    .executableTarget(name:"OriginalDerivativeCurveSourceProof",dependencies:["CADCore","CADGeometry"],path:"Sources/DerivativeCurveProof"),
    .executableTarget(name:"OriginalDerivativeSurfaceSourceProof",dependencies:["CADCore","CADGeometry"],path:"Sources/DerivativeSurfaceProof")
])
