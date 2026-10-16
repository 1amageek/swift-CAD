#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retains constructor join authority; composes only exact station correspondence.
public struct DefaultOriginalFiniteGuideChartPreparer<S:OriginalGuideSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalFiniteGuideChartPreparing
    where F.Source == F.Value,S.Coefficient == F.Value {
    public typealias Source=S
    public typealias ChildSelection=C
    public typealias Field=F
    public init() {}
    public func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        traversals:borrowing [[OriginalRationalChartReceipt<S.Traversal,C,F>]],field:borrowing F,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteGuideChartFamily<S,C,F> {
        let source=copy source,traversals=copy traversals,field=copy field
        do {
            return try a.withProofScope { a in
                try compose(source:source,traversals:traversals,field:field,maximumCharts:maximumCharts,limits:limits,using:&a)
            }
        } catch { throw .init(preserving:error) }
    }
    private func compose<A:ExactScalarAdmission & ~Copyable>(source:OriginalSourceBinding<S>,
        traversals:[[OriginalRationalChartReceipt<S.Traversal,C,F>]],field f:F,maximumCharts:Int,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws -> OriginalFiniteGuideChartFamily<S,C,F> {
        try a.checkpoint();try source.require(limits)
        guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        let n=source.original.originalTraversalCount
        guard n>0,n<Int.max,traversals.count==n,maximumCharts>=0 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        guard try f.compare(f.importing(source.original.originalStation(at:0),using:&a),zero,using:&a) == .equal,
            try f.compare(f.importing(source.original.originalStation(at:n),using:&a),one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidSource }
        var inputCount=0
        for charts in traversals {
            try a.consumeWork(1)
            let next=inputCount.addingReportingOverflow(charts.count)
            guard !next.overflow else { throw OriginalSourceIssuanceFailure.countOverflow };inputCount=next.partialValue
        }
        let capacity=min(inputCount,maximumCharts)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:capacity,of:OriginalGuideChartReceipt<S,C,F>.self))
        var laws:[OriginalGuideChartReceipt<S,C,F>]=[];laws.reserveCapacity(capacity)
        let ring=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        var previousOrdinal = -1
        for index in 0..<n {
            try a.consumeWork(1)
            let binding=source.original.originalTraversal(at:index)
            try binding.require(.init(remainingSourceDepth:limits.remainingSourceDepth-1))
            let ordinal=source.original.originalSegmentOrdinal(at:index)
            guard ordinal>=previousOrdinal,ordinal>=0 else { throw OriginalSourceIssuanceFailure.invalidSource };previousOrdinal=ordinal
            let start=try f.importing(source.original.originalStation(at:index),using:&a)
            let end=try f.importing(source.original.originalStation(at:index+1),using:&a)
            let width=try f.subtracting(end,start,using:&a)
            guard try f.sign(of:width,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:traversals[index].count,of:OriginalSourceParameterInterval<F.Value>.self))
            var coveredRanges:[OriginalSourceParameterInterval<F.Value>]=[];coveredRanges.reserveCapacity(traversals[index].count)
            for child in traversals[index] {
                guard binding.owns(child.chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let range=try OriginalFiniteCurveChartRange<F>.prepare(child,field:f,using:&a)
                let lo=try f.compare(range.lower,zero,using:&a) == .less ? zero:range.lower
                let hi=try f.compare(range.upper,one,using:&a) == .greater ? one:range.upper
                guard try f.compare(lo,hi,using:&a) != .greater else { continue }
                guard laws.count<maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                var order=0
                while order<coveredRanges.count {
                    try a.consumeWork(1)
                    if try f.compare(lo,coveredRanges[order].lower,using:&a) == .less { break };order += 1
                }
                coveredRanges.insert(.init(lower:lo,upper:hi),at:order)
                let localA=try f.dividing(f.subtracting(lo,range.offset,using:&a),range.gain,using:&a)
                let localB=try f.dividing(f.subtracting(hi,range.offset,using:&a),range.gain,using:&a)
                let forward=try f.compare(localA,localB,using:&a) != .greater
                let numerator=try ring.importing(child.parameterTransport.numerators[0],using:&a)
                let denominator=try ring.importing(child.parameterTransport.denominators[0],using:&a)
                let aggregate=try ring.adding(ring.scaled(denominator,by:start,using:&a),ring.scaled(numerator,by:width,using:&a),using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<F>.self))
                var position:[ExactPolynomial<F>]=[];position.reserveCapacity(4)
                for original in child.homogeneous { try a.consumeWork(1);position.append(try ring.importing(original,using:&a)) }
                guard position.count==4 else { throw OriginalSourceIssuanceFailure.invalidChart }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactPolynomial<F>.self))
                laws.append(OriginalGuideChartReceipt(source:source,child:child,traversalIndex:index,originalSegmentOrdinal:ordinal,
                    field:f,polynomials:ring,homogeneous:position,localSupport:.init(lower:forward ? localA:localB,upper:forward ? localB:localA),
                    parameterTransport:.init(numerators:[aggregate],denominators:[denominator]),
                    aggregateSupport:.init(lower:try f.adding(start,f.multiplying(width,lo,using:&a),using:&a),upper:try f.adding(start,f.multiplying(width,hi,using:&a),using:&a)),proofDepth:try a.depth))
            }
            var covered=zero
            for range in coveredRanges {
                try a.consumeWork(1)
                guard try f.compare(range.lower,covered,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
                if try f.compare(range.upper,covered,using:&a) == .greater { covered=range.upper }
            }
            guard try f.compare(covered,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalFiniteGuideChartFamily<S,C,F>.self))
        let result=OriginalFiniteGuideChartFamily(source:source,field:f,support:.init(lower:zero,upper:one),laws:laws,proofDepth:try a.depth)
        try a.checkpoint();return result
    }
}
