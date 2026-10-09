import CADCore
import CADGeometry

@main
struct OriginalOffsetSourceProof {
    static func require(_ value:Bool,line:Int = #line) throws {
        guard value else { print("FAILED M4 actual offset line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    static func main() throws {
        var a=ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        var raw=BSplineSurface3D(uDegree:1,vDegree:2,uKnots:[0,0,1,1],vKnots:[-1,-1,-1,1,1,1],
            controlPoints:[[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)],
                [.init(x:0,y:-1,z:0),.init(x:1,y:-1,z:0)],
                [.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let shape=OffsetSurface3D(source:.bSpline(raw),distance:0.25)
        let provider=OriginalOffsetSnapshotProvider(child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard))
        let source=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(shape,limits:limits,using:&a)
        let child=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:source.original.originalChild,
            field:f,maximumCharts:1,limits:.init(remainingSourceDepth:0),using:&a)
        let family=try DefaultOriginalFiniteNativeOffsetLawPreparer<OriginalOffsetSnapshot<BSplineSurface3D>>().prepare(
            source:source,child:child,maximumCharts:1,limits:limits,using:&a)
        raw.controlPoints[0][0] = .init(x:100,y:100,z:100)
        try family.admitProof(limits:limits,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let law=family.laws[0]
        for v in [-0.5,0.5] {
            let sv=try f.binary64(exactly:v,using:&a)
            try require(law.admitsPosition(at:[half,sv],limits:limits,using:&a))
            let values=[half,sv,one]
            let d=try law.polynomials.evaluated(law.denominator,at:values,using:&a).value
            let z=try f.dividing(law.polynomials.evaluated(law.homogeneous[2],at:values,using:&a).value,d,using:&a)
            let expected=v<0 ? -0.25:0.25
            try require(f.compare(z,f.binary64(exactly:expected,using:&a),using:&a) == .equal)
            let surface=Surface3D.procedural(.offset(shape))
            let point=try surface.point(u:0.5,v:v,tolerance:.standard)
            try require((point-Point3D(x:0.5,y:0.25,z:expected)).length<1e-9)
            let differential=try shape.parameterDerivatives(u:0.5,v:v,tolerance:.standard)
            try require((differential.position-point).length<1e-9 && differential.tangentU.length>0 && differential.tangentV.length>0)
        }
        try require(!law.admitsPosition(at:[half,zero],limits:limits,using:&a))
        for distance in [0.0,0.25] {
            let offset=OffsetSurface3D(source:shape.source,distance:distance)
            do { _ = try offset.point(u:0.5,v:0,tolerance:.standard);throw ExactScalarFailure.invalidEvidence }
            catch let failure as KernelError { try require(failure.code == .singularSystem) }
        }
        let near=try f.binary64(exactly:1e-12,using:&a)
        try require(law.admitsPosition(at:[half,near],limits:limits,using:&a))
        do { _ = try shape.point(u:0.5,v:1e-12,tolerance:.standard);throw ExactScalarFailure.invalidEvidence }
        catch let failure as KernelError { try require(failure.code == .singularSystem) }
        do { _ = try provider.snapshot(shape,limits:.init(remainingSourceDepth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        do { _ = try provider.snapshot(OffsetSurface3D(source:shape.source,distance:.nan),limits:limits,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected {}
        let kink=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,.init(x:1,y:0,z:0),.init(x:2,y:0,z:1)],
                [.init(x:0,y:1,z:0),.init(x:1,y:1,z:0),.init(x:2,y:1,z:1)]])
        let kinkOffset=OffsetSurface3D(source:.bSpline(kink),distance:0.25)
        let kinkSource=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(kinkOffset,limits:limits,using:&a)
        let kinkChild=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(source:kinkSource.original.originalChild,
            field:f,maximumCharts:2,limits:.init(remainingSourceDepth:0),using:&a)
        let kinkFamily=try DefaultOriginalFiniteNativeOffsetLawPreparer<OriginalOffsetSnapshot<BSplineSurface3D>>().prepare(
            source:kinkSource,child:kinkChild,maximumCharts:2,limits:limits,using:&a)
        try require(kinkFamily.laws.count==2 && !kinkFamily.laws[0].ownsUpperBoundary[0])
        try require(!kinkFamily.laws[0].admitsPosition(at:[half,half],limits:limits,using:&a))
        try require(kinkFamily.laws[1].admitsPosition(at:[half,half],limits:limits,using:&a))
        let actualKnot=try kinkOffset.point(u:0.5,v:0.5,tolerance:.standard)
        let shift=0.25/Double(2).squareRoot()
        try require((actualKnot-Point3D(x:1-shift,y:0.5,z:shift)).length<1e-9)
        print("PASS M4 actual guarded Native offset law, signed normal branches, retained source, point/derivative, singular fiber, zero distance and separate numerical admission")
    }
}
