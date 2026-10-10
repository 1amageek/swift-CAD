#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Period-backed fundamental offset laws; guards define actual position support.
public struct OriginalPeriodicNativeOffsetLawFamily<S: OriginalOffsetSourceReading>: Sendable where S.Child: OriginalBSplineSourceReading {
    public let source: OriginalSourceBinding<S>
    public let child: OriginalBSplineFundamentalCharts<S.Child>
    public let laws: [OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>]
    public let proofDepth: ExactScalarDepth
    public var field: OriginalExactScalarDomain { child.field }
    init(source: OriginalSourceBinding<S>,child: OriginalBSplineFundamentalCharts<S.Child>,
        laws: [OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>],proofDepth: ExactScalarDepth) {
        self.source=source;self.child=child;self.laws=laws;self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for period in child.periods {
                try a.consumeWork(1);try period.source.require(limits)
                _=try field.sign(of:period.lower,using:&a)
                _=try field.sign(of:period.upper,using:&a)
                _=try field.sign(of:period.period,using:&a)
            }
            for law in laws { try a.consumeWork(1);try law.admitProof(limits:limits,using:&a) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
