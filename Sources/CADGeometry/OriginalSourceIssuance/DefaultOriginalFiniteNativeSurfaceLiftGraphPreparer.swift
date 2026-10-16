#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<S: OriginalSurfaceLiftSourceReading>: OriginalFiniteNativeSurfaceLiftGraphPreparing {
    public typealias Source = S
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        surface: borrowing OriginalFiniteBSplineCharts<S.Surface>, pcurve: borrowing OriginalFiniteBSplineCharts<S.Pcurve>,
        maximumCharts: Int, limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteNativeSurfaceLiftGraphs<S> {
        let source=copy source,surface=copy surface,pcurve=copy pcurve
        do {
            return try admission.withProofScope { a in
                try a.checkpoint(); try source.require(limits)
                guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard maximumCharts >= 0 else { throw OriginalSourceIssuanceFailure.chartLimit }
                guard source.original.originalSurface.owner === surface.source.owner,
                    source.original.originalPcurve.owner === pcurve.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let childLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                try surface.source.require(childLimits); try pcurve.source.require(childLimits)
                guard surface.source.original.parameterCount == 2, pcurve.source.original.parameterCount == 1,
                    surface.support.count == 2,pcurve.support.count == 1,
                    !surface.laws.isEmpty,!pcurve.laws.isEmpty else { throw OriginalSourceIssuanceFailure.invalidChart }
                let f=surface.field, zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                func validate<C: OriginalBSplineSourceReading>(_ family: OriginalFiniteBSplineCharts<C>,
                    arity: Int, _ a: inout A) throws {
                    for law in family.laws {
                        try a.consumeWork(1);try law.admitProof(using:&a)
                        guard family.source.owns(law.chart),law.polynomials.variableCount == arity,
                            law.support.count == arity,law.homogeneous.count == 4,
                            law.parameterTransport.numerators.count == arity,
                            law.parameterTransport.denominators.count == arity else { throw OriginalSourceIssuanceFailure.invalidChart }
                        for axis in 0..<arity {
                            try a.consumeWork(1)
                            let ring=law.polynomials,d=law.parameterTransport.denominators[axis]
                            guard try !ring.isZero(d,using:&a),try ring.isZero(ring.subtracting(
                                law.parameterTransport.numerators[axis],ring.multiplying(ring.variable(axis,using:&a),d,using:&a),using:&a),using:&a) else {
                                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                            }
                        }
                    }
                }
                try validate(surface,arity:2,&a); try validate(pcurve,arity:1,&a)
                let lower=try f.importing(pcurve.support[0].lower,using:&a)
                let span=try f.subtracting(pcurve.support[0].upper,lower,using:&a)
                guard try f.sign(of:span,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
                let count=surface.laws.count.multipliedReportingOverflow(by:pcurve.laws.count)
                guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                guard count.partialValue <= maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                typealias Family=OriginalFiniteNativeSurfaceLiftGraphs<S>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Family.Graph.self))
                var graphs:[Family.Graph]=[];graphs.reserveCapacity(count.partialValue)
                let producer=OriginalSurfaceLiftGraphProducer<S>()
                for s in surface.laws { for p in pcurve.laws {
                    try a.consumeWork(1)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSurfaceLiftGraphEvidence<S>.self))
                    graphs.append(try producer.issue(source:source,evidence:.init(surface:s,pcurve:p),
                        offset:lower,span:span,using:&a))
                } }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Family.self))
                let result=Family(source:source,surface:surface,pcurve:pcurve,graphs:graphs,
                    support:[.init(lower:zero,upper:one)],proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
