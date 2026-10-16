#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalRevolutionLawIssuer<S:OriginalRevolutionSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalRevolutionLawIssuing where F.Source == F.Value {
    public typealias Source=S
    public typealias GeneratorSelection=C
    public typealias Field=F
    public init() {}
    public func issue<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        generator:borrowing OriginalRationalChartReceipt<S.Generator,C,F>,field:borrowing F,axisLength:F.Value,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalRevolutionLawReceipt<S,C,F> {
        let source=copy source,generator=copy generator,f=copy field
        do {
            return try a.withProofScope { usage in
                try compose(source:source,generator:generator,field:f,axisLength:axisLength,limits:limits,using:&usage)
            }
        } catch { throw .init(preserving:error) }
    }
    private func compose<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<S>,
        generator:OriginalRationalChartReceipt<S.Generator,C,F>,field f:F,axisLength:F.Value,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws -> OriginalRevolutionLawReceipt<S,C,F> {
        try a.checkpoint(); try source.require(limits)
        guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        try generator.source.require(.init(remainingSourceDepth:limits.remainingSourceDepth-1))
        guard source.original.originalGenerator.owns(generator.chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
        guard generator.homogeneous.count == 4 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let range=try OriginalFiniteCurveChartRange<F>.prepare(generator,field:f,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let u0=try f.binary64(exactly:source.original.originalLowerU,using:&a)
        let u1=try f.binary64(exactly:source.original.originalUpperU,using:&a)
        guard try f.compare(u0,u1,using:&a) == .less else { throw OriginalSourceIssuanceFailure.invalidSource }
        let lo=try f.compare(range.lower,zero,using:&a) == .less ? zero:range.lower
        let hi=try f.compare(range.upper,one,using:&a) == .greater ? one:range.upper
        guard try f.compare(lo,hi,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:F.Value.self))
        var origin:[F.Value]=[],axis:[F.Value]=[]
        var norm2=zero
        for i in 0..<3 {
            try a.consumeWork(1)
            origin.append(try f.binary64(exactly:source.original.axisOriginCoordinate(in:i),using:&a))
            let n=try f.binary64(exactly:source.original.axisDirectionCoordinate(in:i),using:&a)
            axis.append(n); norm2=try f.adding(norm2,f.multiplying(n,n,using:&a),using:&a)
        }
        guard try f.sign(of:norm2,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
        guard try f.sign(of:axisLength,using:&a) == .positive,
            try f.compare(norm2,f.multiplying(axisLength,axisLength,using:&a),using:&a) == .equal else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        for i in 0..<3 { axis[i]=try f.dividing(axis[i],axisLength,using:&a) }
        let ring=try ExactPolynomialDomain(field:f,variableCount:3,using:&a)
        let cos=try ring.variable(0,using:&a),sin=try ring.variable(1,using:&a),v=try ring.variable(2,using:&a)
        let t=try ring.scaled(ring.subtracting(v,ring.constant(range.offset,using:&a),using:&a),
            by:f.dividing(one,range.gain,using:&a),using:&a)
        func importCurve(_ p:ExactPolynomial<F>,_ a:inout A) throws -> ExactPolynomial<F> {
            try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<F.Value>.self))
            var terms:[ExactPolynomialTerm<F.Value>]=[]
            for term in p.terms {
                try a.consumeWork(1); try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                terms.append(.init(powers:[0,0,term.powers[0]],coefficient:try f.importing(term.coefficient,using:&a)))
            }
            return try ring.substituted(ring.polynomial(orderedTerms:terms,using:&a),with:[cos,sin,t],using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:16,of:ExactPolynomial<F>.self))
        let d=try importCurve(generator.denominator,&a)
        guard try !ring.isZero(d,using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
        var r:[ExactPolynomial<F>]=[]
        for i in 0..<3 { r.append(try ring.subtracting(importCurve(generator.homogeneous[i],&a),ring.scaled(d,by:origin[i],using:&a),using:&a)) }
        var dot=try ring.constant(zero,using:&a)
        for i in 0..<3 { dot=try ring.adding(dot,ring.scaled(r[i],by:axis[i],using:&a),using:&a) }
        var radial:[ExactPolynomial<F>]=[],axial:[ExactPolynomial<F>]=[]
        for i in 0..<3 { axial.append(try ring.scaled(dot,by:axis[i],using:&a));radial.append(try ring.subtracting(r[i],axial[i],using:&a)) }
        var radial2=try ring.constant(zero,using:&a),position:[ExactPolynomial<F>]=[]
        for i in 0..<3 {
            let j=(i+1)%3,k=(i+2)%3
            let cross=try ring.subtracting(ring.scaled(r[k],by:axis[j],using:&a),ring.scaled(r[j],by:axis[k],using:&a),using:&a)
            let base=try ring.adding(ring.scaled(d,by:origin[i],using:&a),axial[i],using:&a)
            position.append(try ring.adding(base,ring.adding(ring.multiplying(radial[i],cos,using:&a),ring.multiplying(cross,sin,using:&a),using:&a),using:&a))
            radial2=try ring.adding(radial2,ring.multiplying(radial[i],radial[i],using:&a),using:&a)
        }
        position.append(d)
        let parameters=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        let local=try parameters.scaled(parameters.subtracting(parameters.variable(1,using:&a),parameters.constant(range.offset,using:&a),using:&a),by:f.dividing(one,range.gain,using:&a),using:&a)
        let parameterOne=try parameters.constant(one,using:&a)
        let p=try f.binary64(exactly:2*Double.pi,using:&a)
        let upper=try f.adding(u0,p,using:&a)
        let anchor=try source.chart(0,limits:limits,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<F.Value>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalSourceCoordinateFunction<F.Value>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactPolynomial<F>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRevolutionLawReceipt<S,C,F>.self))
        let result=OriginalRevolutionLawReceipt(source:source,generator:generator,field:f,polynomials:ring,homogeneous:position,
            support:[.init(lower:u0,upper:u1),.init(lower:lo,upper:hi)],
            period:.init(anchor:anchor,field:f,meaning:.intrinsicAngularLabel,axis:0,period:p,lower:u0,upper:upper),
            generatorChartParameter:.init(numerators:[local],denominators:[parameterOne]),parameterPolynomials:parameters,
            normalizedAxis:axis,radialSquaredNumerator:radial2,proofDepth:try a.depth)
        try a.checkpoint(); return result
    }
}
