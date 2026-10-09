#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteRevolutionLawPreparer<S:OriginalRevolutionSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:OriginalFiniteRevolutionLawPreparing where F.Source == F.Value {
    public typealias Source=S
    public typealias GeneratorSelection=C
    public typealias Field=F
    public init() {}
    public func issue<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        generator:borrowing OriginalRationalChartReceipt<S.Generator,C,F>,field:borrowing F,axisLength:F.Value,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalRevolutionLawReceipt<S,C,F> {
        try DefaultOriginalRevolutionLawIssuer<S,C,F>().issue(source:source,generator:generator,field:field,axisLength:axisLength,limits:limits,using:&a)
    }
    public func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<S>,
        generators:borrowing [OriginalRationalChartReceipt<S.Generator,C,F>],field:borrowing F,axisLength:F.Value,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRevolutionLawFamily<S,C,F> {
        do {
            let field=copy field,source=copy source,generators=copy generators
            return try OriginalSourceProofAdmission<A>.withBorrow(&a) { a in
            try a.checkpoint();try source.require(limits)
            guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
            let zero=try field.integer(0,using:&a),one=try field.integer(1,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:generators.count,of:OriginalSourceParameterInterval<F.Value>.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:generators.count,of:Int.self))
            var ranges:[OriginalSourceParameterInterval<F.Value>]=[],indices:[Int]=[]
            for i in generators.indices {
                try a.consumeWork(1)
                guard source.original.originalGenerator.owns(generators[i].chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let r=try OriginalFiniteCurveChartRange<F>.prepare(generators[i],field:field,using:&a)
                let lo=try field.compare(r.lower,zero,using:&a) == .less ? zero:r.lower
                let hi=try field.compare(r.upper,one,using:&a) == .greater ? one:r.upper
                if try field.compare(lo,hi,using:&a) != .greater {
                    guard indices.count < maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                    var position=0
                    while position<ranges.count {
                        try a.consumeWork(1)
                        if try field.compare(lo,ranges[position].lower,using:&a) == .less { break }
                        position += 1
                    }
                    ranges.insert(.init(lower:lo,upper:hi),at:position);indices.insert(i,at:position)
                }
            }
            var covered=zero
            for r in ranges {
                try a.consumeWork(1)
                guard try field.compare(r.lower,covered,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
                if try field.compare(r.upper,covered,using:&a) == .greater { covered=r.upper }
            }
            guard try field.compare(covered,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:indices.count,of:OriginalRevolutionLawReceipt<S,C,F>.self))
            var result:[OriginalRevolutionLawReceipt<S,C,F>]=[];result.reserveCapacity(indices.count)
            for i in indices {
                try a.consumeWork(1)
                result.append(try issue(source:source,generator:generators[i],field:field,axisLength:axisLength,limits:limits,using:&a))
            }
            guard let first=result.first else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<F.Value>.self))
            let support=[first.support[0],OriginalSourceParameterInterval(lower:zero,upper:one)]
            let family=OriginalFiniteRevolutionLawFamily(source:source,field:field,laws:result,
                support:support,period:first.period,proofDepth:try a.depth)
            try a.checkpoint();return family
            }
        } catch { throw .init(preserving:error) }
    }
}
