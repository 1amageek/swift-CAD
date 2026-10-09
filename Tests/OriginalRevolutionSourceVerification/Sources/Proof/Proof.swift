import CADCore
@testable import CADGeometry

@main
struct OriginalRevolutionSourceProof {
    static func require(_ value:Bool,line:Int = #line) throws {
        guard value else { print("FAILED M4 actual revolution line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    static func main() throws {
        var a=ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let initial=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let raw=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0)],weights:[1,2])
        let span=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalCurveRootSpan3D(source:.bSpline(raw),start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:0,maximumAlgebraicDepth:0)
        }.value.reversed()
        let shape=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalRevolutionSurface3D(generator:span,axisOrigin:.origin,axisDirection:.init(x:0,y:0,z:2),
                uDomain:.closed(-2*Double.pi,2*Double.pi),tolerance:.standard,usage:&usage)
        }.value
        let provider=OriginalRevolutionSnapshotProvider(child:OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),field:initial,tolerance:.standard)
        let source=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(shape,limits:limits,using:&a)
        let generator=source.original.originalGenerator,f=generator.original.field
        let child=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>().prepare(source:generator.original.originalChild,
            field:f,maximumCharts:2,limits:.init(remainingSourceDepth:0),using:&a)
        let directed=try DefaultOriginalFiniteTraversalChartPreparer<OriginalTraversalSpanSnapshot<BSplineCurve3D>,OriginalBSplineChartSelection,OriginalExactScalarDomain>()
            .prepare(source:generator,children:child.laws,field:f,coefficients:DefaultOriginalSourceCoefficientImporter<OriginalExactScalarDomain>(),
                maximumCharts:2,limits:.init(remainingSourceDepth:1),using:&a)
        let receipts=try DefaultOriginalFiniteRevolutionLawPreparer<OriginalRevolutionSnapshot<BSplineCurve3D>,
            OriginalTraversalChartSelection<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>,OriginalExactScalarDomain>()
            .prepare(source:source,generators:directed,field:f,axisLength:f.integer(2,using:&a),maximumCharts:2,limits:limits,using:&a)
        try require(receipts.laws.count == 1 && source.sourceDepth == 2)
        try receipts.admitProof(limits:limits,using:&a)
        let law=receipts.laws[0],zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let quarter=try f.dividing(one,f.integer(4,using:&a),using:&a)
        let expected=try f.dividing(f.integer(6,using:&a),f.integer(7,using:&a),using:&a)
        let d=try law.polynomials.evaluated(law.denominator,at:[zero,one,quarter],using:&a).value
        let y=try f.dividing(law.polynomials.evaluated(law.homogeneous[1],at:[zero,one,quarter],using:&a).value,d,using:&a)
        try require(f.compare(y,expected,using:&a) == .equal)
        let local=try law.parameterPolynomials.evaluated(law.generatorChartParameter.numerators[0],at:[zero,quarter],using:&a).value
        try require(f.compare(local,f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a),using:&a) == .equal)
        let publicSurface=Surface3D.procedural(.originalRevolution(shape))
        let point=try publicSurface.point(u:Double.pi*0.5,v:0.25,tolerance:.standard)
        try require((point-Point3D(x:0,y:6.0/7,z:0)).length<1e-9)
        let differential=try shape.parameterDerivatives(u:Double.pi*0.5,v:0.25,tolerance:.standard)
        try require((differential.position-point).length<1e-9 && differential.tangentU.length>0 && differential.tangentV.length>0)
        try require(shape.hasOriginalAxisEndpoint(atEnd:true))
        let pole=try publicSurface.point(u:1.25,v:1,tolerance:.standard)
        try require((pole - .origin).length<1e-9)
        try require(f.sign(of:law.polynomials.evaluated(law.radialSquaredNumerator,at:[zero,one,one],using:&a).value,using:&a) == .zero)
        do { _ = try provider.snapshot(shape,limits:.init(remainingSourceDepth:1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let badTolerance=try ModelingTolerance(distance:2*ModelingTolerance.standard.distance,angle:ModelingTolerance.standard.angle,relative:ModelingTolerance.standard.relative)
        let wrong=OriginalRevolutionSnapshotProvider(child:OriginalNativeCurveFamilySnapshotProvider(tolerance:badTolerance),field:initial,tolerance:badTolerance)
        do { _ = try wrong.snapshot(shape,limits:limits,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected {}
        let domainLimits = try OriginalDomainIdentityLimits(source:limits,maximumTransportDepth:16,
            maximumCharts:4,maximumFamilies:1,maximumIdentityProofs:8)
        let domainIssuer = DefaultOriginalRevolutionDomainIssuer<OriginalRevolutionSnapshot<BSplineCurve3D>,
            OriginalTraversalChartSelection<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>,OriginalExactScalarDomain>()
        let domainFrame = try domainIssuer.frame(family:receipts,limits:domainLimits,using:&a)
        let domainCover = try domainIssuer.issue(request:domainFrame.fullSelection(limits:domainLimits,using:&a),
            family:receipts,limits:domainLimits,using:&a)
        let occurrences = try domainCover.incident(at:[zero,quarter],limits:domainLimits,using:&a)
        try require(occurrences.count == 2)
        for occurrence in occurrences {
            try require(occurrence.transport.image.contains([zero,quarter],limits:domainLimits,using:&a))
            let childLocal = try occurrence.law.parameterPolynomials.evaluated(
                occurrence.law.generatorChartParameter.numerators[0],at:[zero,quarter],using:&a).value
            try require(f.compare(childLocal,f.dividing(f.integer(3,using:&a),f.integer(4,using:&a),using:&a),using:&a) == .equal)
        }
        let poleOccurrences = try domainCover.incident(at:[zero,one],limits:domainLimits,using:&a)
        try require(poleOccurrences.count == 2)
        for occurrence in poleOccurrences {
            try require(f.sign(of:occurrence.law.polynomials.evaluated(occurrence.law.radialSquaredNumerator,
                at:[one,zero,one],using:&a).value,using:&a) == .zero)
        }
        print("PASS M4 actual revolution DI cover: exact source/provider/family handoff, all seam sides and collapsed original UV preserved")
        print("PASS M4 actual revolution retained weighted reversed generator, original raw axis, exact source law and public point/derivative/pole/depth/tolerance handoff")
    }
}
