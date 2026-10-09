import CADCore
@testable import CADGeometry

@main
struct OriginalDerivativeCurveSourceProof {
    static func require(_ value:Bool,line:Int = #line) throws {
        guard value else { print("FAILED M4 actual derivative curve line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    static func main() throws {
        var a=ExactScalarLedger(limits:try .init(work:160_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let shape=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let raw=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:1)])
            let source=try OriginalCurveRootSpan3D(source:.bSpline(raw),start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:1,remainingSourceDepth:0,maximumAlgebraicDepth:0)
            let constraint=OriginalPlaneDerivativeConstraint(surface:.plane(.init(origin:.origin,normal:.init(x:0,y:0,z:2))),order:.curvature)
            let endConstraint=OriginalPlaneDerivativeConstraint(surface:.plane(.init(origin:.init(x:0,y:0,z:1),normal:.init(x:0,y:0,z:2))),order:.curvature)
            return try OriginalPlaneDerivativeCurve3D(source:source,startConstraints:[constraint],endConstraints:[endConstraint],
                tolerance:.standard,usage:&usage,remainingSourceDepth:1)
        }.value
        let provider=OriginalPlaneDerivativeCurveSnapshotProvider(field:f,tolerance:.standard)
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let source=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(shape,limits:limits,using:&a)
        try require(source.original.original.startConstraints==shape.startConstraints && source.original.original.source==shape.source)
        let family=try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalPlaneDerivativeCurveSnapshot>().prepare(
            source:source,maximumCharts:1,limits:limits,using:&a)
        try family.admitProof(limits:limits,using:&a);try require(family.laws.count==1)
        let law=family.laws[0],r=law.polynomials
        for (t,expectedZ) in [(0.0,0.0),(0.25,0.103515625),(0.5,0.5),(1.0,1.0)] {
            let parameter=try f.binary64(exactly:t,using:&a)
            let d=try r.evaluated(law.denominator,at:[parameter],using:&a).value
            let z=try f.dividing(r.evaluated(law.homogeneous[2],at:[parameter],using:&a).value,d,using:&a)
            try require(f.compare(z,f.binary64(exactly:expectedZ,using:&a),using:&a) == .equal)
            let point=try shape.point(at:t,tolerance:.standard)
            try require((point-Point3D(x:t,y:0,z:expectedZ)).length<1e-9)
        }
        let derivative=try Curve3D.originalPlaneDerivative(shape).differentialGeometry(at:0.25,tolerance:.standard)
        try require(abs(derivative.firstDerivative.z-1.0546875)<1e-9)
        let start=try Curve3D.originalPlaneDerivative(shape).differentialGeometry(at:0,tolerance:.standard)
        try require(abs(start.firstDerivative.z)<1e-9 && abs(start.secondDerivative.z)<1e-9)
        do { _ = try provider.snapshot(shape,limits:.init(remainingSourceDepth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let bad=ModelingTolerance(distance:2*ModelingTolerance.standard.distance,angle:ModelingTolerance.standard.angle,relative:ModelingTolerance.standard.relative)
        do { _ = try OriginalPlaneDerivativeCurveSnapshotProvider(field:f,tolerance:bad).snapshot(shape,limits:limits,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected {}
        var noStorage=ExactScalarLedger(limits:try .init(work:160_000_000,storageBytes:0,valueDepth:32,coefficientDepth:32))
        do { _ = try provider.snapshot(shape,limits:limits,using:&noStorage);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        print("PASS M4 actual retained plane-derivative original Hermite position, raw-N constraints, point/derivative correspondence and source/storage failures")
    }
}
