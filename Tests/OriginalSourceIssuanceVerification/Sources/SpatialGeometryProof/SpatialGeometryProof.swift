import CADCore
@testable import CADGeometry
import SourceIssuerCached

@main
struct SpatialGeometryProof {
    enum Failure: Error { case incorrectEvidence }
    static func require(_ value: Bool) throws { if !value { throw Failure.incorrectEvidence } }
    static func ledger(work: Int = 20_000_000, storage: Int = 134_217_728) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: storage, valueDepth: 32, coefficientDepth: 32))
    }
    static func main() throws {
        var a = try ledger()
        let raw = OriginalNormalizedAffineSource(family: .axis2, location: .init(x:3,y:4,z:5),
            axis1: .init(x:1,y:1,z:0), axis2:nil, axis3:.unitZ, scale:nil,
            lengthGain:.one, adjustments:[])
        let word = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAffineOperationWord(operation:.normalizedForward(raw), tolerance:.standard,
                maximumDepth:32, usage:&usage)
        }.value
        let original = try OriginalAffineWordCurve3D(source:.analytic(.line(origin:.origin,direction:.unitX)),
            operationWord:word,tolerance:.standard)
        let provider = OriginalAffineWordCurveSnapshotProvider(child:OriginalLinearCurveSnapshotProvider(tolerance:.standard),
            tolerance:.standard,maximumAlgebraicDepth:32)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(original,limits:limits,using:&a)
        let childSource = parent.original.originalChild, field = parent.original.field
        let selected = try childSource.chart(OriginalLinearChartSelection(lower:-2,upper:3),limits:limits,using:&a)
        let child = try DefaultOriginalLinearChartIssuer<OriginalLinearCurveSnapshot,OriginalExactScalarDomain>()
            .issue(source:childSource,chart:selected,field:field,limits:limits,using:&a)
        let chart = try parent.chart(OriginalSpatialChartSelection(child:child),limits:limits,using:&a)
        let issuer = DefaultOriginalSpatialChartIssuer<OriginalAffineWordSnapshot<OriginalAffineWordCurve3D,OriginalLinearCurveSnapshot>,
            OriginalLinearChartSelection,OriginalExactScalarDomain>()
        let result = try issuer.issue(source:parent,chart:chart,field:field,limits:limits,using:&a)
        let alpha = parent.original.spatialCoefficient(row:0,column:0)
        try require(try field.sign(of:alpha,using:&a) == .positive)
        try require(try field.compare(field.multiplying(alpha,alpha,using:&a),
            field.dividing(field.integer(1,using:&a),field.integer(2,using:&a),using:&a),using:&a) == .equal)
        try require(try field.compare(parent.original.spatialCoefficient(row:0,column:1),field.negated(alpha,using:&a),using:&a) == .equal)
        try require(try field.compare(parent.original.spatialCoefficient(row:1,column:0),alpha,using:&a) == .equal)
        let ring = result.polynomials,t = try ring.variable(0,using:&a)
        let scaled = try ring.scaled(t,by:alpha,using:&a)
        for (axis,translation) in [(0,3),(1,4)] {
            let expected = try ring.adding(scaled,ring.constant(field.integer(translation,using:&a),using:&a),using:&a)
            try require(try ring.equals(result.homogeneous[axis],expected,using:&a))
        }
        try require(try ring.equals(result.homogeneous[2],ring.constant(field.integer(5,using:&a),using:&a),using:&a))
        try require(try ring.equals(result.denominator,ring.constant(field.integer(1,using:&a),using:&a),using:&a))
        try require(try field.compare(result.support[0].lower,field.integer(-2,using:&a),using:&a) == .equal)
        try require(try field.compare(result.support[0].upper,field.integer(3,using:&a),using:&a) == .equal)
        try require(result.source.original.original.operationWord == word && result.source.sourceDepth == 1)
        let retained = try OriginalExactScalarDomain(retaining:alpha,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try require(try retained.compare(retained.importing(alpha,using:&a),alpha,using:&a) == .equal)
        // Same-valued separately constructed source roots are different authorities.
        let foreignWord = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAffineOperationWord(operation:.normalizedForward(raw),tolerance:.standard,maximumDepth:32,usage:&usage)
        }.value
        let foreignOriginal = try OriginalAffineWordCurve3D(source:original.source,operationWord:foreignWord,tolerance:.standard)
        let foreign = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(foreignOriginal,limits:limits,using:&a)
        do { _ = try issuer.issue(source:parent,chart:chart,field:foreign.original.field,limits:limits,using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.incompatibleDomain)) {}
        catch OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        let invalidPolicy = OriginalAffineWordCurveSnapshotProvider(
            child:OriginalLinearCurveSnapshotProvider(tolerance:.standard),
            tolerance:.init(distance:0,angle:1e-9),maximumAlgebraicDepth:32)
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:invalidPolicy).bind(original,limits:limits,using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.admissionRejected(let cause)) {
            guard case GeometryError.invalidModelingTolerance = cause else { throw Failure.incorrectEvidence }
        }
        var rejected = try ledger()
        let tight = OriginalAffineWordCurveSnapshotProvider(child:OriginalLinearCurveSnapshotProvider(tolerance:.standard),tolerance:.standard,maximumAlgebraicDepth:0)
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:tight).bind(original,limits:limits,using:&rejected)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.coefficientDepth)) {}
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(original,
            limits:.init(remainingSourceDepth:0),using:&rejected);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        for pair in [(1,134_217_728),(20_000_000,0)] {
            var low = try ledger(work:pair.0,storage:pair.1)
            do { _ = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(original,limits:limits,using:&low)
                throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (pair.0 == 1 ? .work : .storage))
            }
        }
        var cancelled = try ledger();cancelled.cancel()
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(original,limits:limits,using:&cancelled)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS actual normalized original-word line: positive exact sqrt(1/2), full laws, same original field owner, source/field/depth/budget/cancel failures")
        let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:1)]],weights:[[1,2],[3,6]])
        let identityWord = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalAffineOperationWord(factors:[.forward(try .init(basisX:.unitX,basisY:.unitY,basisZ:.unitZ,translation:.zero))],usage:&usage)
        }.value
        let image = try OriginalAffineWordSurface3D(source:.bSpline(native),operationWord:identityWord,tolerance:.standard)
        let surfaceProvider = OriginalAffineWordSurfaceSnapshotProvider(child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),
            tolerance:.standard,maximumAlgebraicDepth:32)
        let surface = try DefaultOriginalSourceBindingIssuer(provider:surfaceProvider).bind(image,limits:limits,using:&a)
        let sf = surface.original.field, sb = surface.original.originalChild
        let sc = try sb.chart(OriginalBSplineChartSelection(spans:[1,1]),limits:limits,using:&a)
        let sr = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,OriginalExactScalarDomain>()
            .issue(source:sb,chart:sc,field:sf,limits:limits,using:&a)
        let pc = try surface.chart(OriginalSpatialChartSelection(child:sr),limits:limits,using:&a)
        let transformed = try DefaultOriginalSpatialChartIssuer<OriginalAffineWordSnapshot<OriginalAffineWordSurface3D,BSplineSurface3D>,
            OriginalBSplineChartSelection,OriginalExactScalarDomain>().issue(source:surface,chart:pc,field:sf,limits:limits,using:&a)
        for axis in 0..<4 {
            try require(try transformed.polynomials.equals(transformed.homogeneous[axis],
                transformed.polynomials.importing(sr.homogeneous[axis],using:&a),using:&a))
        }
        try require(transformed.parameterTransport.numerators.count == 2 && transformed.support.count == 2)
        print("PASS actual rational original-word weighted tensor retains all four original laws, both parameter transports and product denominator")
    }
}
