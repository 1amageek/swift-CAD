import CADCore
@testable import CADGeometry

@main
struct OriginalGuideSourceProof {
    static func require(_ value:Bool,line:Int = #line) throws {
        guard value else { print("FAILED M4 actual guide line \(line)");throw ExactScalarFailure.invalidEvidence }
    }
    static func main() throws {
        var a=ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        var spans:[OriginalCurveRootSpan3D]=[]
        for controls in [[Point3D.origin,Point3D(x:1,y:0,z:0)],[Point3D(x:3,y:0,z:0),Point3D(x:1,y:0,z:0)]] {
            let reversed=spans.count==1
            let raw=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:controls,weights:reversed ? [1,2]:[1,1])
            let span=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalCurveRootSpan3D(source:.bSpline(raw),start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                    maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                    storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:0,maximumAlgebraicDepth:0)
            }.value
            spans.append(reversed ? span.reversed():span)
        }
        let shape=try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let third=try ExactRationalCoefficient.one.divided(by:.originalDouble(3,usage:&usage),usage:&usage)
            return try OriginalGuideTraversalChain3D(traversals:spans,stations:[.zero,third,.one],sourceSegmentOrdinals:[3,7],
                remainingSourceDepth:2,tolerance:.standard,usage:&usage)
        }.value
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let provider=OriginalGuideSnapshotProvider(child:OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),field:f,tolerance:.standard)
        let source=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(shape,limits:limits,using:&a)
        let final=source.original.field
        typealias Selection=OriginalTraversalChartSelection<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>
        var children:[[OriginalRationalChartReceipt<OriginalTraversalSpanSnapshot<BSplineCurve3D>,Selection,OriginalExactScalarDomain>]]=[]
        for traversal in source.original.traversals {
            let native=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>().prepare(source:traversal.original.originalChild,
                field:final,maximumCharts:2,limits:.init(remainingSourceDepth:0),using:&a)
            children.append(try DefaultOriginalFiniteTraversalChartPreparer<OriginalTraversalSpanSnapshot<BSplineCurve3D>,OriginalBSplineChartSelection,OriginalExactScalarDomain>()
                .prepare(source:traversal,children:native.laws,field:final,coefficients:DefaultOriginalSourceCoefficientImporter<OriginalExactScalarDomain>(),
                    maximumCharts:2,limits:.init(remainingSourceDepth:1),using:&a))
        }
        let family=try DefaultOriginalFiniteGuideChartPreparer<OriginalGuideSnapshot<BSplineCurve3D>,Selection,OriginalExactScalarDomain>().prepare(
            source:source,traversals:children,field:final,maximumCharts:2,limits:limits,using:&a)
        try family.admitProof(limits:limits,using:&a)
        let one=try final.integer(1,using:&a),zero=try final.integer(0,using:&a)
        let third=try final.dividing(one,final.integer(3,using:&a),using:&a)
        try require(final.compare(family.laws[0].aggregateSupport.upper,third,using:&a) == .equal)
        try require(final.compare(family.laws[1].aggregateSupport.lower,third,using:&a) == .equal)
        for (index,t,expectedT,expectedX) in [(0,0.5,1.0/6,0.5),(1,0.5,2.0/3,5.0/3)] {
            let law=family.laws[index],local=try final.binary64(exactly:t,using:&a)
            let d=try law.polynomials.evaluated(law.parameterTransport.denominators[0],at:[local],using:&a).value
            let aggregate=try final.dividing(law.polynomials.evaluated(law.parameterTransport.numerators[0],at:[local],using:&a).value,d,using:&a)
            let expected=index==0 ? try final.dividing(one,final.integer(6,using:&a),using:&a):try final.multiplying(third,final.integer(2,using:&a),using:&a)
            try require(final.compare(aggregate,expected,using:&a) == .equal)
            let point=try Curve3D.originalGuideTraversalChain(shape).point(at:expectedT,tolerance:.standard)
            try require((point-Point3D(x:expectedX,y:0,z:0)).length<1e-9)
        }
        for (index,local) in [(0,one),(1,one)] {
            let law=family.laws[index]
            let x=try final.dividing(law.polynomials.evaluated(law.homogeneous[0],at:[local],using:&a).value,
                law.polynomials.evaluated(law.homogeneous[3],at:[local],using:&a).value,using:&a)
            try require(final.compare(x,one,using:&a) == .equal)
        }
        do { _ = try provider.snapshot(shape,limits:.init(remainingSourceDepth:1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let bad=ModelingTolerance(distance:2*ModelingTolerance.standard.distance,angle:ModelingTolerance.standard.angle,relative:ModelingTolerance.standard.relative)
        let wrong=OriginalGuideSnapshotProvider(child:OriginalNativeCurveFamilySnapshotProvider(tolerance:bad),field:f,tolerance:bad)
        do { _ = try wrong.snapshot(shape,limits:limits,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected {}
        print("PASS M4 actual original guide constructor, retained traversals, exact 1/3 station, aggregate law/point correspondence, both joins and explicit failures")
    }
}
