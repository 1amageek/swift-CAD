import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif

@main struct CertifiedCoaxialSourceAcceptance {
    static func require(_ value: Bool) throws { guard value else { throw ExactScalarFailure.invalidEvidence } }
    static func main() throws {
        let angle=atan(0.5)
        let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:angle))
        let cylinder=Surface3D.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:1))
        let sourceLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        for kind in [CertifiedConeCylinderIntersectionCurve.ComponentKind.negativeFullBranch,.positiveFullBranch] {
            // Each independently admitted public query owns its unchanged allowance.
            var a=ExactScalarLedger(limits:try .init(work:1_000_000,storageBytes:8_388_608,valueDepth:32,coefficientDepth:32))
            let field=try OriginalPhysicalAngleScalarDomain(originalRadians:angle,using:&a)
            let provider=OriginalCertifiedCoaxialConeCylinderSnapshotProvider(field:field,tolerance:.standard)
            let sine=try field.sine(using:&a),cosine=try field.cosine(using:&a)
            let original=try CertifiedConeCylinderIntersectionCurve(coneSurface:cone,cylinderSurface:cylinder,
                componentKind:kind,lowerAngle:0,upperAngle:2*Double.pi,tolerance:.standard)
            let snapshot=try provider.snapshot(.certifiedIntersection(.coneCylinder(original)),limits:sourceLimits,using:&a)
            let law=snapshot.original
            try require(snapshot.sourceDepth==1 && law.original==original)
            let sigma=try field.integer(kind == .negativeFullBranch ? 1:-1,using:&a)
            try require(field.compare(field.multiplying(law.height,sine,using:&a),
                field.multiplying(sigma,cosine,using:&a),using:&a) == .equal)
            try require(field.compare(field.multiplying(law.coneSlant,sine,using:&a),sigma,using:&a) == .equal)
            // These whole-field identities prove the original selected cone root.
            // A second numerical sign refinement of an unrelated metric is unnecessary.
        }
        print("PASS both exact original coaxial roots and intrinsic cylinder traversal authority")
    }
}
