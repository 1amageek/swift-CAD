#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<S: OriginalSurfaceLiftSourceReading>: OriginalPeriodicNativeSurfaceLiftGraphPreparing {
    public typealias Source=S
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        surface: borrowing OriginalBSplineFundamentalCharts<S.Surface>,
        pcurve: borrowing OriginalFiniteBSplineCharts<S.Pcurve>,maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPeriodicNativeSurfaceLiftGraphs<S> {
        let source=copy source,surface=copy surface,pcurve=copy pcurve
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try source.require(limits)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard source.original.originalSurface.owner === surface.source.owner,
                    source.original.originalPcurve.owner === pcurve.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let childLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                try surface.source.require(childLimits);try pcurve.source.require(childLimits)
                guard surface.support.count==2,pcurve.support.count==1,
                    surface.source.original.parameterCount==2,pcurve.source.original.parameterCount==1,
                    !surface.periods.isEmpty,!surface.laws.isEmpty,!pcurve.laws.isEmpty else { throw OriginalSourceIssuanceFailure.invalidChart }
                let count=surface.laws.count.multipliedReportingOverflow(by:pcurve.laws.count)
                guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                guard maximumCharts>=0,count.partialValue<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                func validate<C: Sendable,K: Sendable>(_ law: OriginalRationalChartReceipt<C,K,OriginalExactScalarDomain>,
                    owner: OriginalSourceBinding<C>,arity: Int) throws {
                    try a.consumeWork(1);try law.admitProof(using:&a)
                    guard owner.owns(law.chart),law.polynomials.variableCount==arity,law.support.count==arity,
                        law.homogeneous.count==4,law.parameterTransport.numerators.count==arity,
                        law.parameterTransport.denominators.count==arity else { throw OriginalSourceIssuanceFailure.invalidChart }
                    for axis in 0..<arity {
                        try a.consumeWork(1)
                        let r=law.polynomials,d=law.parameterTransport.denominators[axis]
                        guard try !r.isZero(d,using:&a),try r.isZero(r.subtracting(law.parameterTransport.numerators[axis],
                            r.multiplying(r.variable(axis,using:&a),d,using:&a),using:&a),using:&a) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    }
                }
                for law in surface.laws { try validate(law,owner:surface.source,arity:2) }
                for law in pcurve.laws { try validate(law,owner:pcurve.source,arity:1) }
                for period in surface.periods {
                    try a.consumeWork(1);try period.source.require(childLimits)
                    guard surface.source.owns(period.anchor) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                    _=try surface.field.sign(of:period.period,using:&a)
                    _=try surface.field.sign(of:period.lower,using:&a);_=try surface.field.sign(of:period.upper,using:&a)
                }
                let f=surface.field,lower=try f.importing(pcurve.support[0].lower,using:&a)
                let span=try f.subtracting(f.importing(pcurve.support[0].upper,using:&a),lower,using:&a)
                guard try f.sign(of:span,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
                let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPeriodicNativeSurfaceLiftGraphs<S>.self))
                let result=OriginalPeriodicNativeSurfaceLiftGraphs(source:source,surface:surface,pcurve:pcurve,
                    count:count.partialValue,proofDepth:try a.depth,support:[.init(lower:zero,upper:one)],offset:lower,span:span)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
