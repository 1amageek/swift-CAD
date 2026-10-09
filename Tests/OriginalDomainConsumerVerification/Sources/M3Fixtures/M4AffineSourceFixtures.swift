import CADCore
@testable import CADGeometry

/// Actual source providers feed the same composition contract as independent proofs.
public enum M4AffineSourceFixtures {
    private static func require(_ value: Bool) throws {
        guard value else { throw ExactScalarFailure.invalidEvidence }
    }
    private static func native<S: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>(
        _ source: OriginalSourceBinding<S>, field: F, limits: OriginalDomainIdentityLimits,
        using a: inout ExactScalarLedger) throws -> OriginalBSplineDomainCover<S,F> {
        let issuer = DefaultOriginalBSplineDomainIssuer<S,F>()
        let space = try issuer.prepare(source: source, field: field, limits: limits, using: &a)
        return try issuer.issue(space: space, request: space.frame.fullSelection(limits: limits, using: &a), limits: limits, using: &a)
    }
    public static func verify() throws {
        var a = ExactScalarLedger(limits: try .init(work:80_000_000, storageBytes:1_073_741_824, valueDepth:32, coefficientDepth:32))
        let l = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:2),maximumTransportDepth:16,
            maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:64)
        let f = ExactRationalScalarDomain()
        let raw = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0)],weights:[1,2])
        let image = try ParameterImageCurve3D(source:.bSpline(raw),parameterGain:.ratio(numerator:-3,denominator:2),offset:0.25,tolerance:.standard)
        let provider = OriginalParameterImageCurveSnapshotProvider(child:OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),tolerance:.standard)
        let source = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(image,limits:l.source,using:&a)
        let child = try native(source.original.originalChild,field:f,limits:l,using:&a)
        let cover = try DefaultOriginalParameterImageDomainIssuer<OriginalParameterImageSnapshot<ParameterImageCurve3D,BSplineCurve3D>,OriginalBSplineDomainCover<BSplineCurve3D,ExactRationalScalarDomain>>()
            .issue(source:source,child:child,limits:l,using:&a)
        let quarter = try f.dividing(f.integer(1,using:&a),f.integer(4,using:&a),using:&a)
        let occurrence = try cover.incident(at:[f.integer(0,using:&a)],limits:l,using:&a)
        try require(occurrence.count == 1)
        let parent = try DefaultOriginalParameterTransporter<OriginalParameterImageSnapshot<ParameterImageCurve3D,BSplineCurve3D>,ExactRationalScalarDomain>()
            .forward([quarter],through:occurrence[0].correspondence,limits:l,using:&a)
        try require(f.sign(of:parent[0],using:&a) == .zero)
        try require((Curve3D.parameterImage(image).point(at:0,tolerance:.standard)-Curve3D.bSpline(raw).point(at:0.25,tolerance:.standard)).length < 1e-9)

        let tensor = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:1)]],weights:[[1,2],[3,6]])
        let transform = try AffineTransform3D(basisX:.init(x:2,y:1,z:0),basisY:.init(x:1,y:3,z:0),basisZ:.init(x:0,y:0,z:4),translation:.init(x:0.25,y:-0.5,z:2))
        let surface = try OriginalImageSurface3D(source:.bSpline(tensor),uParameterGain:.ratio(numerator:-6,denominator:7),
            vParameterGain:.ratio(numerator:5,denominator:9),uOffset:0.5,vOffset:0.25,transform:transform,swapAxes:true,tolerance:.standard)
        let s = try DefaultOriginalSourceBindingIssuer(provider:OriginalParameterImageSurfaceSnapshotProvider(
            child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),tolerance:.standard)).bind(surface,limits:l.source,using:&a)
        let tensorChild = try native(s.original.originalChild,field:f,limits:l,using:&a)
        let mapped = try DefaultOriginalParameterImageDomainIssuer<OriginalParameterImageSnapshot<OriginalImageSurface3D,BSplineSurface3D>,OriginalBSplineDomainCover<BSplineSurface3D,ExactRationalScalarDomain>>()
            .issue(source:s,child:tensorChild,limits:l,using:&a)
        let uv = [try f.dividing(f.integer(-7,using:&a),f.integer(24,using:&a),using:&a),try f.integer(0,using:&a)]
        let selected = try mapped.incident(at:uv,limits:l,using:&a)
        try require(selected.count == 1)
        let imagePoint = try Surface3D.procedural(.originalImage(surface)).point(u:-7.0/24,v:0,tolerance:.standard)
        let childPoint = try Surface3D.bSpline(tensor).point(u:0.25,v:0.75,tolerance:.standard)
        try require((imagePoint-transform.applying(to:childPoint)).length < 1e-9)

        let domain = try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let span = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalCurveRootSpan3D(source:.bSpline(raw),start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,remainingSourceDepth:0,maximumAlgebraicDepth:0)
        }.value.reversed()
        let traversal = try DefaultOriginalSourceBindingIssuer(provider:OriginalTraversalSpanSnapshotProvider(
            child:OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),field:domain)).bind(span,limits:l.source,using:&a)
        let traversedChild = try native(traversal.original.originalChild,field:domain,limits:l,using:&a)
        let directed = try DefaultOriginalTraversalDomainIssuer<OriginalTraversalSpanSnapshot<BSplineCurve3D>,OriginalBSplineDomainCover<BSplineCurve3D,OriginalExactScalarDomain>>()
            .issue(source:traversal,child:traversedChild,limits:l,using:&a)
        let zero = try domain.integer(0,using:&a),one = try domain.integer(1,using:&a)
        let end = try directed.incident(at:[zero],limits:l,using:&a)
        try require(end.count == 1)
        let start = try DefaultOriginalParameterTransporter<OriginalTraversalSpanSnapshot<BSplineCurve3D>,OriginalExactScalarDomain>()
            .forward([one],through:end[0].correspondence,limits:l,using:&a)
        try require(domain.sign(of:start[0],using:&a) == .zero)
        let word = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAffineOperationWord(operation:.forward(transform),tolerance:.standard,maximumDepth:32,usage:&usage)
        }.value
        let authoredWord = try OriginalAffineWordCurve3D(source:.bSpline(raw),operationWord:word,tolerance:.standard)
        let wordSource = try DefaultOriginalSourceBindingIssuer(provider:OriginalAffineWordCurveSnapshotProvider(
            child:OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),tolerance:.standard,maximumAlgebraicDepth:32))
            .bind(authoredWord,limits:l.source,using:&a)
        let wordField = wordSource.original.field
        let wordChild = try native(wordSource.original.originalChild,field:wordField,limits:l,using:&a)
        let wordCover = try DefaultOriginalSpatialChildDomainIssuer<OriginalAffineWordSnapshot<OriginalAffineWordCurve3D,BSplineCurve3D>,OriginalBSplineDomainCover<BSplineCurve3D,OriginalExactScalarDomain>>()
            .issue(source:wordSource,child:wordChild,limits:l,using:&a)
        try require(wordCover.incident(at:[wordField.binary64(exactly:0.25,using:&a)],limits:l,using:&a).count == 1)
        print("PASS M4 actual weighted curve/image surface swapped axes, spatial action, exact gains and reversed root-span domain handoff")
    }
}
