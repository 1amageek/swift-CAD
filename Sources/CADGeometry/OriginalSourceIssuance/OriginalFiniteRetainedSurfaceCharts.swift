#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed original whole square with every retained producer cell side.
public struct OriginalFiniteRetainedSurfaceCharts<S:OriginalRetainedSurfaceSourceReading>:Sendable {
    public let source:OriginalSourceBinding<S>
    public let field:S.Field
    public let support:[OriginalSourceParameterInterval<S.Field.Value>]
    public let laws:[OriginalRationalChartReceipt<S,Int,S.Field>]
    public let proofDepth:ExactScalarDepth
    init(source:OriginalSourceBinding<S>,field:S.Field,support:[OriginalSourceParameterInterval<S.Field.Value>],
        laws:[OriginalRationalChartReceipt<S,Int,S.Field>],proofDepth:ExactScalarDepth) {
        self.source=source;self.field=field;self.support=support;self.laws=laws;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for law in laws { try a.consumeWork(1);try law.admitProof(using:&a) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
