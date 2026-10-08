import CADCore
@testable import CADGeometry
import SourceIssuerCached

@main
struct CoonsGeometryProof {
    enum Failure: Error { case incorrectEvidence }
    typealias F = OriginalExactScalarDomain
    typealias S = OriginalTraversalSpanSnapshot<BSplineCurve3D>
    typealias Selection = OriginalTraversalChartSelection<BSplineCurve3D, OriginalBSplineChartSelection, F>
    typealias Boundary = OriginalCoonsBoundarySelection<S, Selection, F>
    typealias Coons = OriginalCoonsSurfaceSnapshot<BSplineCurve3D, BSplineCurve3D, BSplineCurve3D, BSplineCurve3D>
    static let tolerance = ModelingTolerance(distance: 1e-9, angle: 1e-10)
    static func require(_ value: Bool) throws { if !value { throw Failure.incorrectEvidence } }
    static func ledger(work: Int = 80_000_000, storage: Int = 134_217_728) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: storage, valueDepth: 32, coefficientDepth: 32))
    }
    static func span(_ native: BSplineCurve3D, _ lower: Double, _ upper: Double,
        reversed: Bool, using a: inout ExactScalarLedger) throws -> OriginalCurveRootSpan3D {
        let raw = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalCurveRootSpan3D(source: .bSpline(native), start: .authored(lower), end: .authored(upper),
                nativeSpanIndex: native.degree, maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: 0,
                tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                maximumSpanCount: 2, remainingSourceDepth: 0, maximumAlgebraicDepth: 0)
        }.value
        return reversed ? raw.reversed() : raw
    }
    static func construction(reversed: Bool) throws -> OriginalCoonsSurface3D {
        var a = try ledger()
        var bottom = BSplineCurve3D(degree: 2, knots: [-2,-2,-2,4,4,4],
            controlPoints: [.origin,.init(x:1,y:0,z:1),.init(x:2,y:0,z:0)], weights: [1,2,1])
        if reversed { bottom.controlPoints.reverse(); bottom.weights.reverse() }
        let top = BSplineCurve3D(degree:1,knots:[7,7,10,10],
            controlPoints:[.init(x:0,y:2,z:0),.init(x:2,y:2,z:0)],weights:[1,3])
        let left = BSplineCurve3D(degree:1,knots:[1,1,5,5],
            controlPoints:[.origin,.init(x:0,y:2,z:0)],weights:[2,1])
        let right = BSplineCurve3D(degree:1,knots:[-5,-5,-1,-1],
            controlPoints:[.init(x:2,y:0,z:0),.init(x:2,y:2,z:0)],weights:[1,2])
        let b = try span(bottom,-2,4,reversed:reversed,using:&a)
        let t = try span(top,7,10,reversed:false,using:&a)
        let l = try span(left,1,5,reversed:false,using:&a)
        let r = try span(right,-5,-1,reversed:false,using:&a)
        return try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalCoonsSurface3D(vMinimumBoundary:b,vMaximumBoundary:t,
                uMinimumBoundary:l,uMaximumBoundary:r,tolerance:tolerance,usage:&usage)
        }.value
    }
    static func boundary(_ source: OriginalSourceBinding<S>, field: F,
        using a: inout ExactScalarLedger) throws -> Boundary {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let child = source.original.originalChild
        let selected = try child.chart(OriginalBSplineChartSelection(spans:[source.original.original.nativeSpanIndex ?? child.original.degree]),
            limits:limits,using:&a)
        let native = try DefaultOriginalBSplineChartIssuer<BSplineCurve3D,F>()
            .issue(source:child,chart:selected,field:field,limits:limits,using:&a)
        let chart = try source.chart(Selection(child:native),limits:limits,using:&a)
        let curve = try DefaultOriginalTraversalChartIssuer<S,OriginalBSplineChartSelection,F>()
            .issue(source:source,chart:chart,field:field,limits:limits,using:&a)
        let issuer = DefaultOriginalCurveEndpointIssuer<S,Selection,F>()
        let start = try issuer.issue(source:source,curve:curve,localParameter:source.original.originalStart,
            originalParameter:field.integer(0,using:&a),limits:limits,using:&a)
        let end = try issuer.issue(source:source,curve:curve,localParameter:source.original.originalEnd,
            originalParameter:field.integer(1,using:&a),limits:limits,using:&a)
        return .init(curve:curve,start:start,end:end)
    }
    static func coons(reversed: Bool) throws {
        let raw = try construction(reversed:reversed)
        var a = try ledger(); let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let child = OriginalNativeCurveFamilySnapshotProvider(tolerance:tolerance)
        let provider = OriginalCoonsSurfaceSnapshotProvider(bottom:child,top:child,left:child,right:child,field:f,tolerance:tolerance)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(raw,limits:limits,using:&a)
        let field = parent.original.field
        let b = try boundary(parent.original.bottomBoundary,field:field,using:&a)
        let t = try boundary(parent.original.topBoundary,field:field,using:&a)
        let l = try boundary(parent.original.leftBoundary,field:field,using:&a)
        let e = try boundary(parent.original.rightBoundary,field:field,using:&a)
        let chart = try parent.chart(OriginalCoonsChartSelection(bottom:b,top:t,left:l,right:e),limits:limits,using:&a)
        let result = try DefaultOriginalCoonsChartIssuer<Coons,Selection,Selection,Selection,Selection,F>()
            .issue(source:parent,chart:chart,field:field,limits:limits,using:&a)
        let r = result.polynomials
        let u = try r.variable(0,using:&a), v = try r.variable(1,using:&a)
        let one = try r.constant(field.integer(1,using:&a),using:&a)
        let zero = try r.zero(using:&a)
        func scale(_ p: ExactPolynomial<F>, _ n: Int) throws -> ExactPolynomial<F> {
            try r.scaled(p,by:field.integer(n,using:&a),using:&a)
        }
        func add(_ p: ExactPolynomial<F>, _ q: ExactPolynomial<F>) throws -> ExactPolynomial<F> { try r.adding(p,q,using:&a) }
        func sub(_ p: ExactPolynomial<F>, _ q: ExactPolynomial<F>) throws -> ExactPolynomial<F> { try r.subtracting(p,q,using:&a) }
        func mul(_ p: ExactPolynomial<F>, _ q: ExactPolynomial<F>) throws -> ExactPolynomial<F> { try r.multiplying(p,q,using:&a) }
        let u2 = try mul(u,u), um = try sub(one,u), vm = try sub(one,v)
        let wb = try sub(add(one,scale(u,2)),scale(u2,2))
        let wt = try add(one,scale(u,2)), wl = try sub(scale(one,2),v), we = try add(one,v)
        let weights = [wb,wt,wl,we]
        let laws = [[try sub(scale(u,4),scale(u2,2)),zero,try sub(scale(u,4),scale(u2,4))],
            [try scale(u,6),try scale(wt,2),zero], [zero,try scale(v,2),zero],
            [try scale(we,2),try scale(v,4),zero]]
        let blends = [vm,v,um,u]
        var w = one
        for weight in weights { w = try mul(w,weight) }
        for axis in 0..<4 {
            var expected = w
            if axis < 3 {
                expected = zero
                for boundary in 0..<4 {
                    var other = one
                    for index in 0..<4 where index != boundary { other = try mul(other,weights[index]) }
                    expected = try add(expected,mul(mul(laws[boundary][axis],other),blends[boundary]))
                }
                let corner = axis == 0 ? try scale(u,2) : axis == 1 ? try scale(v,2) : zero
                expected = try sub(expected,mul(corner,w))
            }
            expected = try scale(expected,reversed ? -288 : 288)
            try require(try r.equals(result.homogeneous[axis],expected,using:&a))
        }
        try require(parent.sourceDepth == 2 && parent.original.bottomBoundary.sourceDepth == 1)
        for axis in 0..<2 {
            try require(try field.compare(result.support[axis].lower,field.integer(0,using:&a),using:&a) == .equal)
            try require(try field.compare(result.support[axis].upper,field.integer(1,using:&a),using:&a) == .equal)
        }
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(raw,limits:.init(remainingSourceDepth:1),using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        for pair in [(1,134_217_728),(80_000_000,0)] {
            var low = try ledger(work:pair.0,storage:pair.1)
            do { _ = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(raw,limits:limits,using:&low)
                throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(let resource)) {
                try require(resource == (pair.0 == 1 ? .work : .storage))
            }
        }
        var cancel = try ledger();cancel.cancel()
        do { _ = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(raw,limits:limits,using:&cancel)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS actual weighted nonunit Coons complete HXYZW, signed traversal, exact corners, owned sources, depth/work/storage/cancel: reversed=\(reversed)")
    }
    static func algebraicTraversal(reversed: Bool) throws {
        // Source construction is separate from the measured issuer query. The
        // producer receives these existing sealed endpoints and never searches.
        var preparation = try ledger()
        let native = BSplineCurve3D(degree:2,knots:[0,0,0,2,2,2],
            controlPoints:[.origin,.init(x:0,y:1,z:0),.init(x:4,y:2,z:0)],weights:[1,1,1])
        func endpoint(_ constant: Double, lower: Double, upper: Double) throws -> OriginalCurveRootBoundary {
            try ExactScalarNumericAccess.withAdmission(&preparation) { usage in
                let t2 = try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&usage)
                let p = try t2.subtracting(.constant(.originalDouble(constant,usage:&usage),usage:&usage),usage:&usage)
                return try OriginalCurveRootBoundary(source:native,spanIndex:2,constraint:.parameterPolynomial(p),
                    isolationLower:.originalDouble(lower,usage:&usage),isolationUpper:.originalDouble(upper,usage:&usage),
                    maximumSubdivisionDepth:32,tolerance:tolerance,usage:&usage)
            }.value
        }
        let two = try endpoint(2,lower:1,upper:1.5),three = try endpoint(3,lower:1.5,upper:2)
        let original = try ExactScalarNumericAccess.withAdmission(&preparation) { usage in
            try OriginalCurveRootSpan3D(source:.bSpline(native),start:.algebraic(two),end:.algebraic(three),
                nativeSpanIndex:2,maximumParameterWidth:0.25,maximumSubdivisionDepth:32,tolerance:tolerance,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,
                remainingSourceDepth:0,maximumAlgebraicDepth:32)
        }.value
        let raw = reversed ? original.reversed() : original
        var a = try ledger();let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let provider = OriginalTraversalSpanSnapshotProvider(child:OriginalNativeCurveFamilySnapshotProvider(tolerance:tolerance),field:f)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let source = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(raw,limits:limits,using:&a)
        let field = source.original.field
        let b = try boundary(source,field:field,using:&a)
        let first = source.original.originalStart,last = source.original.originalEnd
        for (value,constant) in [(first,reversed ? 3 : 2),(last,reversed ? 2 : 3)] {
            try require(try field.compare(field.multiplying(value,value,using:&a),field.integer(constant,using:&a),using:&a) == .equal)
        }
        try require(try field.compare(first,last,using:&a) == (reversed ? .greater : .less))
        let r = b.curve.polynomials,t = try r.variable(0,using:&a)
        try require(try r.equals(b.curve.homogeneous[0],r.multiplying(t,t,using:&a),using:&a))
        try require(try r.equals(b.curve.homogeneous[1],t,using:&a))
        try require(try r.equals(b.curve.parameterTransport.numerators[0],
            r.subtracting(t,r.constant(first,using:&a),using:&a),using:&a))
        try require(try r.equals(b.curve.parameterTransport.denominators[0],
            r.constant(field.subtracting(last,first,using:&a),using:&a),using:&a))
        try require(try field.compare(b.start.position[0],field.integer(reversed ? 3 : 2,using:&a),using:&a) == .equal)
        try require(try field.compare(b.end.position[0],field.integer(reversed ? 2 : 3,using:&a),using:&a) == .equal)
        try require(try field.compare(b.start.position[1],first,using:&a) == .equal)
        try require(try field.compare(b.end.position[1],last,using:&a) == .equal)
        try require(try field.compare(b.curve.support[0].lower,reversed ? last : first,using:&a) == .equal)
        try require(try field.compare(b.curve.support[0].upper,reversed ? first : last,using:&a) == .equal)
        print("PASS actual sealed algebraic traversal, ancestor coefficient embedding, original endpoint XYZ and signed exact support: reversed=\(reversed)")
    }
    static func algebraicCoons() throws {
        var preparation = try ledger()
        // The exact integer control net represents 3(t^2-2)(t^2-3),
        // so both algebraic endpoints are the same original corner.
        let native = BSplineCurve3D(degree:4,knots:[0,0,0,0,0,2,2,2,2,2],
            controlPoints:[18,18,8,-12,6].map { .init(x:Double($0),y:0,z:0) })
        let span = try ExactScalarNumericAccess.withAdmission(&preparation) { usage in
            let t2 = try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&usage)
            func root(_ constant: Double,_ lower: Double,_ upper: Double) throws -> OriginalCurveRootBoundary {
                let p = try t2.subtracting(.constant(.originalDouble(constant,usage:&usage),usage:&usage),usage:&usage)
                return try .init(source:native,spanIndex:4,constraint:.parameterPolynomial(p),
                    isolationLower:.originalDouble(lower,usage:&usage),isolationUpper:.originalDouble(upper,usage:&usage),
                    maximumSubdivisionDepth:32,tolerance:tolerance,usage:&usage)
            }
            let first = try root(2,1,1.5),last = try root(3,1.5,2)
            return try OriginalCurveRootSpan3D(source:.bSpline(native),start:.algebraic(first),end:.algebraic(last),
                nativeSpanIndex:4,maximumParameterWidth:0.25,maximumSubdivisionDepth:32,tolerance:tolerance,
                storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:2,
                remainingSourceDepth:0,maximumAlgebraicDepth:32)
        }.value
        let raw = try ExactScalarNumericAccess.withAdmission(&preparation) { usage in
            try OriginalCoonsSurface3D(vMinimumBoundary:span,vMaximumBoundary:span,
                uMinimumBoundary:span,uMaximumBoundary:span,tolerance:tolerance,usage:&usage)
        }.value
        var a = try ledger();let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let child = OriginalNativeCurveFamilySnapshotProvider(tolerance:tolerance)
        let provider = OriginalCoonsSurfaceSnapshotProvider(bottom:child,top:child,left:child,right:child,field:f,tolerance:tolerance)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:provider).bind(raw,limits:limits,using:&a)
        let field = parent.original.field
        let b = try boundary(parent.original.bottomBoundary,field:field,using:&a)
        let t = try boundary(parent.original.topBoundary,field:field,using:&a)
        let l = try boundary(parent.original.leftBoundary,field:field,using:&a)
        let e = try boundary(parent.original.rightBoundary,field:field,using:&a)
        let chart = try parent.chart(OriginalCoonsChartSelection(bottom:b,top:t,left:l,right:e),limits:limits,using:&a)
        let result = try DefaultOriginalCoonsChartIssuer<Coons,Selection,Selection,Selection,Selection,F>()
            .issue(source:parent,chart:chart,field:field,limits:limits,using:&a)
        let r = result.polynomials
        let start = parent.original.bottomBoundary.original.originalStart
        let extent = try field.subtracting(parent.original.bottomBoundary.original.originalEnd,start,using:&a)
        func expected(_ axis: Int) throws -> ExactPolynomial<F> {
            let t = try r.adding(r.constant(start,using:&a),r.scaled(r.variable(axis,using:&a),by:extent,using:&a),using:&a)
            let t2 = try r.multiplying(t,t,using:&a)
            let first = try r.subtracting(t2,r.constant(field.integer(2,using:&a),using:&a),using:&a)
            let last = try r.subtracting(t2,r.constant(field.integer(3,using:&a),using:&a),using:&a)
            return try r.scaled(r.multiplying(first,last,using:&a),by:field.integer(3,using:&a),using:&a)
        }
        let square = try field.multiplying(extent,extent,using:&a)
        let scale = try field.multiplying(square,square,using:&a)
        try require(try r.equals(result.homogeneous[0],r.scaled(r.adding(expected(0),expected(1),using:&a),by:scale,using:&a),using:&a))
        try require(try r.isZero(result.homogeneous[1],using:&a) && r.isZero(result.homogeneous[2],using:&a))
        try require(try r.equals(result.homogeneous[3],r.constant(scale,using:&a),using:&a))
        print("PASS actual four algebraic Coons boundaries retain eight endpoint owners in one field, exact repeated-root corners and complete HXYZW")
    }
    static func main() throws {
        try coons(reversed:false)
        try coons(reversed:true)
        try algebraicTraversal(reversed:false)
        try algebraicTraversal(reversed:true)
        try algebraicCoons()
    }
}
