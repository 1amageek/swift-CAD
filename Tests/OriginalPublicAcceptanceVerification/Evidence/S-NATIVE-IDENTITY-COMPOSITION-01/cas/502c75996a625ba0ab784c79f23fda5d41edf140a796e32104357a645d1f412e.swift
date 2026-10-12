#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed whole-source supply retaining every normalized generator chart side.
public struct OriginalFiniteRevolutionLawFamily<S:OriginalRevolutionSourceReading,C:Sendable,
    F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:Sendable where F.Source == F.Value {
    public let source:OriginalSourceBinding<S>
    public let field:F
    public let laws:[OriginalRevolutionLawReceipt<S,C,F>]
    public let support:[OriginalSourceParameterInterval<F.Value>]
    public let period:OriginalSourcePeriodReceipt<S,F>
    public let proofDepth:ExactScalarDepth
    init(source:OriginalSourceBinding<S>,field:F,laws:[OriginalRevolutionLawReceipt<S,C,F>],
        support:[OriginalSourceParameterInterval<F.Value>],period:OriginalSourcePeriodReceipt<S,F>,proofDepth:ExactScalarDepth) {
        self.source=source;self.field=field;self.laws=laws;self.support=support
        self.period=period;self.proofDepth=proofDepth
    }
    public func admitProof<A:ExactScalarAdmission & ~Copyable>(limits:OriginalSourceIssuanceLimits,
        using a:inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for interval in support {
                try a.consumeWork(1)
                _ = try field.compare(interval.lower,interval.upper,using:&a)
            }
            _ = try field.sign(of:period.period,using:&a)
            for law in laws { try a.consumeWork(1);try law.admitProof(limits:limits,using:&a) }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
