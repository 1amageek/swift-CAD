import CADCore
@testable import CADGeometry
import SourceIssuerCached

@main
struct ParameterGeometryProof {
    enum Failure: Error { case incorrectEvidence }
    static func require(_ value: Bool) throws { if !value { throw Failure.incorrectEvidence } }
    static func ledger(work: Int = 20_000_000, storage: Int = 134_217_728) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:storage,valueDepth:32,coefficientDepth:32))
    }
    static func main() throws {
        var a = try ledger();let f = ExactRationalScalarDomain()
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        var native = BSplineCurve3D(degree:1,knots:[0,0,1,1],
            controlPoints:[.origin,.init(x:1,y:0,z:0)],weights:[1,2])
        let product = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalParameterGain.originalProduct(factors:[.ratio(numerator:3,denominator:7),
                .ratio(numerator:-11,denominator:2)],usage:&usage)
        }.value
        let difference = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalParameterGain.originalDifference(originalLower:0.1,originalUpper:1.3,
                periodicTranslation:.init(originalSourcePeriod:1,originalTurnCount:0,parameterGain:.binary(1)),usage:&usage)
        }.value
        let curveProvider = OriginalParameterImageCurveSnapshotProvider(
            child:OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),tolerance:.standard)
        let issuer = DefaultOriginalParameterImageChartIssuer<OriginalParameterImageSnapshot<ParameterImageCurve3D,BSplineCurve3D>,
            OriginalBSplineChartSelection,ExactRationalScalarDomain>()
        for (index,gain) in [OriginalParameterGain.binary(2),.ratio(numerator:1,denominator:3),product,difference].enumerated() {
            let image = try ParameterImageCurve3D(source:.bSpline(native),parameterGain:gain,offset:0.25,tolerance:.standard)
            let parent = try DefaultOriginalSourceBindingIssuer(provider:curveProvider).bind(image,limits:limits,using:&a)
            let source = parent.original.originalChild
            let selected = try source.chart(OriginalBSplineChartSelection(spans:[1]),limits:limits,using:&a)
            let child = try DefaultOriginalBSplineChartIssuer<BSplineCurve3D,ExactRationalScalarDomain>()
                .issue(source:source,chart:selected,field:f,limits:limits,using:&a)
            let chart = try parent.chart(OriginalParameterImageChartSelection(child:child),limits:limits,using:&a)
            let result = try issuer.issue(source:parent,chart:chart,field:f,limits:limits,using:&a)
            let r = result.polynomials,t = try r.variable(0,using:&a)
            let expectedGain: ExactRationalCoefficient
            switch index {
            case 0: expectedGain = try f.integer(2,using:&a)
            case 1: expectedGain = try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a)
            case 2: expectedGain = try f.dividing(f.integer(-33,using:&a),f.integer(14,using:&a),using:&a)
            default: expectedGain = try f.subtracting(f.binary64(exactly:1.3,using:&a),f.binary64(exactly:0.1,using:&a),using:&a)
            }
            try require(try r.equals(result.parameterTransport.numerators[0],
                r.subtracting(t,r.constant(f.binary64(exactly:0.25,using:&a),using:&a),using:&a),using:&a))
            try require(try r.equals(result.parameterTransport.denominators[0],r.constant(expectedGain,using:&a),using:&a))
            for axis in 0..<4 { try require(try r.equals(result.homogeneous[axis],r.importing(child.homogeneous[axis],using:&a),using:&a)) }
            try require(result.source.sourceDepth == 1 && result.source.original.original.parameterGain == gain)
            if index == 1 { try require(try f.compare(expectedGain,f.binary64(exactly:1.0/3.0,using:&a),using:&a) != .equal) }
        }
        let retained = try ParameterImageCurve3D(source:.bSpline(native),parameterGain:product,offset:0.25,tolerance:.standard)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:curveProvider).bind(retained,limits:limits,using:&a)
        native.controlPoints[1].x = 99;native.weights[1] = 9
        try require(parent.original.originalChild.original.controlPoints[1].x == 1 && parent.original.originalChild.original.weights[1] == 2)
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:curveProvider).bind(retained,
            limits:.init(remainingSourceDepth:0),using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        for pair in [(1,134_217_728),(20_000_000,0)] {
            var low = try ledger(work:pair.0,storage:pair.1)
            do { _ = try DefaultOriginalSourceBindingIssuer(provider:curveProvider).bind(retained,limits:limits,using:&low)
                throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (pair.0 == 1 ? .work : .storage))
            }
        }
        var cancel = try ledger();cancel.cancel()
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:curveProvider).bind(retained,limits:limits,using:&cancel)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        let invalid = ParameterImageCurve3D(validatedSource:retained.source,parameterGain:.binary(0),offset:0)
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:curveProvider).bind(invalid,limits:limits,using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected(let cause) {
            guard case GeometryConversionError.invalidInput = cause else { throw Failure.incorrectEvidence }
        }
        print("PASS actual parameter curve binary/ratio/product/difference, exact nonrepresentable gain, child law/support/owner and source/depth/budgets/cancel")
        let tensor = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,.init(x:1,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:1)]],weights:[[1,2],[3,6]])
        let transform = try AffineTransform3D(basisX:.init(x:2,y:1,z:0),basisY:.init(x:1,y:3,z:0),
            basisZ:.init(x:0,y:0,z:4),translation:.init(x:0.25,y:-0.5,z:2))
        let image = try OriginalImageSurface3D(source:.bSpline(tensor),uParameterGain:.ratio(numerator:-6,denominator:7),
            vParameterGain:.ratio(numerator:5,denominator:9),uOffset:0.5,vOffset:0.25,transform:transform,swapAxes:true,tolerance:.standard)
        let provider = OriginalParameterImageSurfaceSnapshotProvider(child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),tolerance:.standard)
        let surface = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(image,limits:limits,using:&a)
        let sb = surface.original.originalChild,sc = try sb.chart(OriginalBSplineChartSelection(spans:[1,1]),limits:limits,using:&a)
        let child = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,ExactRationalScalarDomain>()
            .issue(source:sb,chart:sc,field:f,limits:limits,using:&a)
        let chart = try surface.chart(OriginalParameterImageChartSelection(child:child),limits:limits,using:&a)
        let result = try DefaultOriginalParameterImageChartIssuer<OriginalParameterImageSnapshot<OriginalImageSurface3D,BSplineSurface3D>,
            OriginalBSplineChartSelection,ExactRationalScalarDomain>().issue(source:surface,chart:chart,field:f,limits:limits,using:&a)
        let r = result.polynomials,u = try r.variable(0,using:&a),v = try r.variable(1,using:&a)
        for (axis,local,offset,n,d) in [(0,v,0.5,-6,7),(1,u,0.25,5,9)] {
            try require(try r.equals(result.parameterTransport.numerators[axis],
                r.subtracting(local,r.constant(f.binary64(exactly:offset,using:&a),using:&a),using:&a),using:&a))
            try require(try r.equals(result.parameterTransport.denominators[axis],
                r.constant(f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),using:&a),using:&a))
        }
        for (axis,coefficients) in [(0,[2.0,1,0,0.25]),(1,[1,3,0,-0.5]),(2,[0,0,4,2])] {
            var expected = try r.zero(using:&a)
            for column in 0..<4 {
                expected = try r.adding(expected,r.scaled(r.importing(child.homogeneous[column],using:&a),
                    by:f.binary64(exactly:coefficients[column],using:&a),using:&a),using:&a)
            }
            try require(try r.equals(result.homogeneous[axis],expected,using:&a))
        }
        try require(try r.equals(result.denominator,r.importing(child.denominator,using:&a),using:&a))
        for axis in 0..<2 {
            try require(try f.compare(result.support[axis].lower,f.integer(0,using:&a),using:&a) == .equal)
            try require(try f.compare(result.support[axis].upper,f.integer(1,using:&a),using:&a) == .equal)
        }
        print("PASS actual parameter surface swapped original axes, signed ratios, complete spatial H/W and unrounded child-local support")
    }
}
