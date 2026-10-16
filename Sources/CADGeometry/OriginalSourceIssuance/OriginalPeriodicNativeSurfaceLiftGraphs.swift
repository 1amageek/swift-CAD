#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Every fundamental chart pair and exact integer translate, without finite enumeration.
public struct OriginalPeriodicNativeSurfaceLiftGraphs<S: OriginalLiftSourceReading>: OriginalPeriodicNativeSurfaceLiftGraphQuerying {
    public typealias Source=S
    public typealias Graph=OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>
    public let source: OriginalSourceBinding<S>
    public let surface: OriginalBSplineFundamentalCharts<S.Surface>
    public let pcurveLaws: [OriginalRationalChartReceipt<S.Pcurve,S.PcurveSelection,OriginalExactScalarDomain>]
    let pcurveField: OriginalExactScalarDomain
    let pcurveSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public let templateCount: Int
    public let proofDepth: ExactScalarDepth
    public let enclosingSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public var field: OriginalExactScalarDomain { surface.field }
    public var integerFamilyRank: Int { surface.periods.count }
    let offset: OriginalExactScalar
    let span: OriginalExactScalar
    init(source: OriginalSourceBinding<S>,surface: OriginalBSplineFundamentalCharts<S.Surface>,
        pcurveLaws: [OriginalRationalChartReceipt<S.Pcurve,S.PcurveSelection,OriginalExactScalarDomain>],
        pcurveField: OriginalExactScalarDomain,pcurveSupport: [OriginalSourceParameterInterval<OriginalExactScalar>],
        count: Int,proofDepth: ExactScalarDepth,
        support: [OriginalSourceParameterInterval<OriginalExactScalar>],offset: OriginalExactScalar,span: OriginalExactScalar) {
        self.source=source;self.surface=surface;self.pcurveLaws=pcurveLaws
        self.pcurveField=pcurveField;self.pcurveSupport=pcurveSupport;templateCount=count
        self.proofDepth=proofDepth;enclosingSupport=support;self.offset=offset;self.span=span
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            guard maximumCharts>=0,templateCount<=maximumCharts else { throw OriginalSourceIssuanceFailure.chartLimit }
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for period in surface.periods {
                try a.consumeWork(1);try period.source.require(limits)
                _=try field.sign(of:period.period,using:&a)
                _=try field.sign(of:period.lower,using:&a);_=try field.sign(of:period.upper,using:&a)
            }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
    public func graph<A: ExactScalarAdmission & ~Copyable>(template: Int,
        cycles: borrowing [ExactRationalCoefficient],maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> Graph {
        let cycles=copy cycles
        do {
            return try admission.withProofScope { a in
                try admitProof(maximumCharts:maximumCharts,limits:limits,using:&a)
                guard (0..<templateCount).contains(template),cycles.count==2 else { throw OriginalSourceIssuanceFailure.invalidChart }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalExactScalar.self))
                var shift:[OriginalExactScalar]=[];shift.reserveCapacity(2)
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    guard cycles[axis].canonicalDenominatorWords == [1] else { throw OriginalSourceIssuanceFailure.invalidChart }
                    let cycle=try field.rational(exactly:cycles[axis],using:&a)
                    var period: OriginalSourcePeriodReceipt<S.Surface,OriginalExactScalarDomain>?=nil
                    for proof in surface.periods { try a.consumeWork(1);if proof.axis==axis { period=proof } }
                    if let period { shift.append(try field.multiplying(cycle,period.period,using:&a)) }
                    else {
                        guard try field.sign(of:cycle,using:&a) == .zero else { throw OriginalSourceIssuanceFailure.invalidChart }
                        shift.append(cycle)
                    }
                }
                let s=surface.laws[template/pcurveLaws.count],p=pcurveLaws[template%pcurveLaws.count]
                try s.admitProof(using:&a);try p.admitProof(using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSurfaceLiftGraphEvidence<S>.self))
                return try OriginalSurfaceLiftGraphProducer<S>().issue(source:source,
                    evidence:.init(surface:s,pcurve:p,surfaceTranslation:shift),offset:offset,span:span,using:&a)
            }
        } catch { throw .init(preserving:error) }
    }
}

// Preserve the original typed Native child view without allocating or copying laws.
extension OriginalPeriodicNativeSurfaceLiftGraphs where S: OriginalSurfaceLiftSourceReading {
    public var pcurve: OriginalFiniteBSplineCharts<S.Pcurve> {
        .init(source:source.original.originalPcurve,field:pcurveField,support:pcurveSupport,laws:pcurveLaws)
    }
}
