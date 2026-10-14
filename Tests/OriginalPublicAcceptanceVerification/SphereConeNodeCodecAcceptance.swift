import CADCore
import CADGeometry
import CADIR
#if canImport(Darwin)
import Foundation
#endif

@main struct SphereConeNodeCodecAcceptance {
    struct Failure: Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { guard value else { throw Failure(line:line) } }
    static func main() throws {
        let sphere=Surface3D.analytic(.sphere(center:.origin,radius:1))
        let cone=Surface3D.analytic(.cone(apex:.init(x:1,y:0,z:0),axis:.unitZ,halfAngle:0.5))
        let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:sphere,second:cone,tolerance:.standard)
        guard case .originalApexSphereCone(let component)=result.intersections[0] else { throw Failure(line:#line) }
        let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:1,
            maximumCharts:2,maximumFamilies:3,maximumIdentityProofs:0)
        let scalar=try ExactScalarLimits(work:8_388_608,storageBytes:268_435_456,valueDepth:32,coefficientDepth:32)
        let codec=PortableSourceEncodingLimits(maximumBytes:16_777_216,maximumWork:16_777_216,maximumDepth:32)
        for branch in 0..<2 {
            var a=ExactScalarLedger(limits:scalar)
            let curve=try component.nodeCurve(branch:branch,tolerance:.standard,limits:limits,using:&a)
            guard case .certifiedIntersection(.sphereCone(let value))=curve else { throw Failure(line:#line) }
            var encoder=try PortableSourceEncoder(limits:codec)
            do { try value.encodeSource(to:&encoder);throw Failure(line:#line) }
            catch let error as KernelError { try require(error.code == .unsupportedCapability) }
            try require(encoder.bytes.isEmpty)
#if canImport(Darwin)
            do { _=try JSONEncoder().encode(value);throw Failure(line:#line) }
            catch is EncodingError {}
#endif
        }
        let legacy=try CertifiedSphereConeIntersectionCurve(
            sphereSurface:.analytic(.sphere(center:.origin,radius:3)),
            coneSurface:.analytic(.cone(apex:.init(x:1,y:0,z:-4),axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50))),
            componentKind:.positiveFullBranch,lowerAngle:0,upperAngle:2*Double.pi,tolerance:.standard)
        try require(legacy.originalNodeTraversal==nil)
        var encoder=try PortableSourceEncoder(limits:codec);try legacy.encodeSource(to:&encoder)
        try require(!encoder.bytes.isEmpty)
#if canImport(Darwin)
        let decoded=try JSONDecoder().decode(CertifiedSphereConeIntersectionCurve.self,from:JSONEncoder().encode(legacy))
        try require(decoded==legacy && decoded.originalNodeTraversal==nil)
#endif
        print("PASS actual portable codec refuses generated proof loss; legacy source and Codable preserved")
    }
}
