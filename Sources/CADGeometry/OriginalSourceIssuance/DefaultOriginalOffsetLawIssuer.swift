#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original rational-child differential normal; no root approximation.
public struct DefaultOriginalOffsetLawIssuer<S:OriginalOffsetSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalOffsetLawIssuing where F.Source == F.Value,S.Child:OriginalBSplineSourceReading {
    public typealias Source=S
    public typealias ChildSelection=C
    public typealias Field=F
    public init() {}
    public func issue<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        child:borrowing OriginalRationalChartReceipt<S.Child,C,F>,field:borrowing F,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalOffsetLawReceipt<S,C,F> {
        let source=copy source,child=copy child,field=copy field
        do {
            return try a.withProofScope { usage in
                try compose(source:source,child:child,field:field,limits:limits,using:&usage)
            }
        } catch { throw .init(preserving:error) }
    }
    private func compose<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<S>,
        child:OriginalRationalChartReceipt<S.Child,C,F>,field f:F,limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws -> OriginalOffsetLawReceipt<S,C,F> {
        try a.checkpoint();try source.require(limits)
        guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        try child.source.require(.init(remainingSourceDepth:limits.remainingSourceDepth-1))
        guard source.original.originalChild.owns(child.chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
        guard child.polynomials.variableCount==2,child.support.count==2,child.homogeneous.count==4,
            child.parameterTransport.numerators.count==2,child.parameterTransport.denominators.count==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let original=child.source.original
        guard original.parameterCount==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Bool.self))
        var ownsUpper:[Bool]=[];ownsUpper.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            let end=try f.binary64(exactly:original.knot(at:original.controlCount(in:axis),in:axis),using:&a)
            // The original periodic evaluator wraps the upper endpoint to the lower side.
            let final = try f.compare(child.support[axis].upper,end,using:&a) == .equal
            ownsUpper.append(!original.isPeriodic(in:axis) && final)
        }
        try child.admitProof(using:&a)
        let r=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        for axis in 0..<2 {
            let n=try r.importing(child.parameterTransport.numerators[axis],using:&a)
            let d=try r.importing(child.parameterTransport.denominators[axis],using:&a)
            guard try !r.isZero(d,using:&a),
                try r.isZero(r.subtracting(n,r.multiplying(r.variable(axis,using:&a),d,using:&a),using:&a),using:&a) else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
        }
        let ring=try ExactPolynomialDomain(field:f,variableCount:3,using:&a)
        func embed(_ p:ExactPolynomial<F>,_ a:inout A) throws -> ExactPolynomial<F> {
            try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<F.Value>.self))
            var terms:[ExactPolynomialTerm<F.Value>]=[];terms.reserveCapacity(p.termCount)
            for term in p.terms {
                try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                terms.append(.init(powers:[term.powers[0],term.powers[1],0],coefficient:try f.importing(term.coefficient,using:&a)))
            }
            return try ring.polynomial(orderedTerms:terms,using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:20,of:ExactPolynomial<F>.self))
        let d=try embed(child.denominator,&a),du=try ring.differentiated(d,in:0,using:&a),dv=try ring.differentiated(d,in:1,using:&a)
        guard try !ring.isZero(d,using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
        var n:[ExactPolynomial<F>]=[],tu:[ExactPolynomial<F>]=[],tv:[ExactPolynomial<F>]=[]
        for i in 0..<3 {
            let value=try embed(child.homogeneous[i],&a);n.append(value)
            tu.append(try ring.subtracting(ring.multiplying(ring.differentiated(value,in:0,using:&a),d,using:&a),ring.multiplying(value,du,using:&a),using:&a))
            tv.append(try ring.subtracting(ring.multiplying(ring.differentiated(value,in:1,using:&a),d,using:&a),ring.multiplying(value,dv,using:&a),using:&a))
        }
        var cross:[ExactPolynomial<F>]=[]
        var square=try ring.constant(f.integer(0,using:&a),using:&a)
        for i in 0..<3 {
            let j=(i+1)%3,k=(i+2)%3
            let value=try ring.subtracting(ring.multiplying(tu[j],tv[k],using:&a),ring.multiplying(tu[k],tv[j],using:&a),using:&a)
            cross.append(value);square=try ring.adding(square,ring.multiplying(value,value,using:&a),using:&a)
        }
        let q=try ring.variable(2,using:&a),distance=try f.binary64(exactly:source.original.originalDistance,using:&a)
        var position:[ExactPolynomial<F>]=[]
        for i in 0..<3 {
            position.append(try ring.adding(ring.multiplying(q,n[i],using:&a),ring.scaled(ring.multiplying(d,cross[i],using:&a),by:distance,using:&a),using:&a))
        }
        position.append(try ring.multiplying(q,d,using:&a))
        let equation=try ring.subtracting(ring.multiplying(q,q,using:&a),square,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalOffsetLawReceipt<S,C,F>.self))
        let result=OriginalOffsetLawReceipt(source:source,child:child,field:f,polynomials:ring,homogeneous:position,
            normalSquared:square,positiveRootEquation:equation,ownsUpperBoundary:ownsUpper,proofDepth:try a.depth)
        try a.checkpoint();return result
    }
}
