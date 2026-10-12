#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed whole aggregate support; every original traversal chart side is retained.
public struct OriginalFiniteGuideChartFamily<S:OriginalGuideSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:Sendable where F.Source == F.Value {
    public let source:OriginalSourceBinding<S>
    public let field:F
    public let support:OriginalSourceParameterInterval<F.Value>
    public let laws:[OriginalGuideChartReceipt<S,C,F>]
    public let proofDepth:ExactScalarDepth
    init(source:OriginalSourceBinding<S>,field:F,support:OriginalSourceParameterInterval<F.Value>,
        laws:[OriginalGuideChartReceipt<S,C,F>],proofDepth:ExactScalarDepth) {
        self.source=source;self.field=field;self.support=support;self.laws=laws;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for law in laws { try a.consumeWork(1);try law.admitProof(limits:limits,using:&a) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
