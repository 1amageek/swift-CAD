#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact owner transfer and whole authored coverage, without source-law rebuilding.
public struct DefaultOriginalFiniteRetainedCurveChartPreparer<S:OriginalRetainedCurveSourceReading>:OriginalFiniteRetainedCurveChartPreparing {
    public typealias Source=S
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedCurveCharts<S> {
        let source=copy source
        do {
            return try a.withProofScope { a in
                try compose(source:source,maximumCharts:maximumCharts,limits:limits,using:&a)
            }
        } catch { throw .init(preserving:error) }
    }
    private func compose<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<S>,maximumCharts:Int,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws -> OriginalFiniteRetainedCurveCharts<S> {
        try a.checkpoint();try source.require(limits)
        let inherited=source.original.originalProofDepth
        try a.admitDepth(value:inherited.value,coefficient:inherited.coefficient)
        let n=source.original.originalCellCount,f=source.original.originalField
        guard n>0,maximumCharts>=0,source.original.originalPolynomials.variableCount==1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        guard n<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
        let ring=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let t=try ring.variable(0,using:&a),d=try ring.constant(one,using:&a)
        typealias Law=OriginalRationalChartReceipt<S,Int,S.Field>
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Law.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:OriginalSourceParameterInterval<S.Field.Value>.self))
        var laws:[Law]=[],ranges:[OriginalSourceParameterInterval<S.Field.Value>]=[]
        laws.reserveCapacity(n);ranges.reserveCapacity(n)
        for index in 0..<n {
            try a.consumeWork(1)
            let original=source.original.originalCellHomogeneous(at:index)
            guard original.count==4 else { throw OriginalSourceIssuanceFailure.invalidChart }
            let lo=try f.importing(source.original.originalCellLowerBound(at:index),using:&a),
                hi=try f.importing(source.original.originalCellUpperBound(at:index),using:&a)
            guard try f.compare(lo,zero,using:&a) != .less,try f.compare(hi,one,using:&a) != .greater,
                try f.compare(lo,hi,using:&a) == .less else { throw OriginalSourceIssuanceFailure.invalidChart }
            let range=OriginalSourceParameterInterval(lower:lo,upper:hi)
            var order=0
            while order<ranges.count {
                try a.consumeWork(1)
                if try f.compare(lo,ranges[order].lower,using:&a) == .less { break };order += 1
            }
            ranges.insert(range,at:order)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<S.Field>.self))
            var position:[ExactPolynomial<S.Field>]=[];position.reserveCapacity(4)
            for p in original { try a.consumeWork(1);position.append(try ring.importing(p,using:&a)) }
            guard try !ring.isZero(position[3],using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<S.Field.Value>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactPolynomial<S.Field>.self))
            laws.append(.init(chart:try source.chart(index,limits:limits,using:&a),field:f,polynomials:ring,
                homogeneous:position,support:[range],parameterTransport:.init(numerators:[t],denominators:[d]),proofDepth:try a.depth))
        }
        var covered=zero
        for range in ranges {
            try a.consumeWork(1)
            guard try f.compare(range.lower,covered,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
            if try f.compare(range.upper,covered,using:&a) == .greater { covered=range.upper }
        }
        guard try f.compare(covered,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalFiniteRetainedCurveCharts<S>.self))
        let result=OriginalFiniteRetainedCurveCharts(source:source,field:f,support:.init(lower:zero,upper:one),laws:laws,proofDepth:try a.depth)
        try a.checkpoint();return result
    }
}
