#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<S: OriginalRetainedPcurveLiftSourceReading>: Sendable {
    public typealias Source = S
    public init() {}
    private func prepared<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        surfaceSource: OriginalSourceBinding<S.Surface>,
        surfaceLaws: [OriginalRationalChartReceipt<S.Surface,S.SurfaceSelection,OriginalExactScalarDomain>],
        surfaceSupport: [OriginalSourceParameterInterval<OriginalExactScalar>],field: OriginalExactScalarDomain,
        surfaceDepth: ExactScalarDepth?,pcurve: OriginalFiniteRetainedCurveCharts<S.Pcurve>,
        maximumCharts: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedSurfaceLiftGraphs<S> {
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try source.require(limits)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard maximumCharts>=0 else { throw OriginalSourceIssuanceFailure.chartLimit }
                guard source.original.originalSurface.owner === surfaceSource.owner,
                    source.original.originalPcurve.owner === pcurve.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let childLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                try surfaceSource.require(childLimits);try pcurve.admitProof(limits:childLimits,using:&a)
                if let surfaceDepth { try a.admitDepth(value:surfaceDepth.value,coefficient:surfaceDepth.coefficient) }
                guard surfaceSupport.count == 2,
                    !surfaceLaws.isEmpty,!pcurve.laws.isEmpty else { throw OriginalSourceIssuanceFailure.invalidChart }
                let f=field,zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                guard try f.compare(f.importing(pcurve.support.lower,using:&a),zero,using:&a) == .equal,
                    try f.compare(f.importing(pcurve.support.upper,using:&a),one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
                func validate<C: Sendable,K: Sendable>(_ law: OriginalRationalChartReceipt<C,K,OriginalExactScalarDomain>,
                    source: OriginalSourceBinding<C>,arity: Int,_ a: inout OriginalSourceProofAdmission<A>) throws {
                    try a.consumeWork(1);try law.admitProof(using:&a)
                    guard source.owns(law.chart),law.polynomials.variableCount == arity,law.support.count == arity,
                        law.homogeneous.count == 4,law.parameterTransport.numerators.count == arity,
                        law.parameterTransport.denominators.count == arity else { throw OriginalSourceIssuanceFailure.invalidChart }
                    for axis in 0..<arity {
                        try a.consumeWork(1)
                        let ring=law.polynomials,d=law.parameterTransport.denominators[axis]
                        guard try !ring.isZero(d,using:&a),try ring.isZero(ring.subtracting(law.parameterTransport.numerators[axis],
                            ring.multiplying(ring.variable(axis,using:&a),d,using:&a),using:&a),using:&a) else {
                            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                        }
                    }
                }
                for law in surfaceLaws { try validate(law,source:surfaceSource,arity:2,&a) }
                for law in pcurve.laws { try validate(law,source:pcurve.source,arity:1,&a) }
                let count=surfaceLaws.count.multipliedReportingOverflow(by:pcurve.laws.count)
                guard !count.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                guard count.partialValue<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
                typealias Family=OriginalFiniteRetainedSurfaceLiftGraphs<S>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Family.Graph.self))
                var graphs:[Family.Graph]=[];graphs.reserveCapacity(count.partialValue)
                let producer=OriginalSurfaceLiftGraphProducer<S>()
                for s in surfaceLaws { for p in pcurve.laws {
                    try a.consumeWork(1)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSurfaceLiftGraphEvidence<S>.self))
                    graphs.append(try producer.issue(source:source,evidence:.init(surface:s,pcurve:p),offset:zero,span:one,using:&a))
                } }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Family.self))
                let result=Family(source:source,surfaceSource:surfaceSource,surfaceLaws:surfaceLaws,
                    surfaceSupport:surfaceSupport,field:f,pcurve:pcurve,graphs:graphs,
                    support:[.init(lower:zero,upper:one)],proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}

extension DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer: OriginalFiniteRetainedSurfaceLiftGraphPreparing
    where S: OriginalRetainedSurfaceLiftSourceReading {
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        surface: borrowing OriginalFiniteBSplineCharts<S.Surface>,pcurve: borrowing OriginalFiniteRetainedCurveCharts<S.Pcurve>,
        maximumCharts: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedSurfaceLiftGraphs<S> {
        try prepared(source:source,surfaceSource:surface.source,surfaceLaws:surface.laws,
            surfaceSupport:surface.support,field:surface.field,surfaceDepth:nil,pcurve:pcurve,
            maximumCharts:maximumCharts,limits:limits,using:&admission)
    }
}

extension DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer: OriginalFiniteRetainedAtlasLiftGraphPreparing
    where S: OriginalRetainedAtlasLiftSourceReading {
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        surface: borrowing OriginalFiniteRetainedSurfaceCharts<S.Surface>,pcurve: borrowing OriginalFiniteRetainedCurveCharts<S.Pcurve>,
        maximumCharts: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRetainedSurfaceLiftGraphs<S> {
        try prepared(source:source,surfaceSource:surface.source,surfaceLaws:surface.laws,
            surfaceSupport:surface.support,field:surface.field,surfaceDepth:surface.proofDepth,pcurve:pcurve,
            maximumCharts:maximumCharts,limits:limits,using:&admission)
    }
}
