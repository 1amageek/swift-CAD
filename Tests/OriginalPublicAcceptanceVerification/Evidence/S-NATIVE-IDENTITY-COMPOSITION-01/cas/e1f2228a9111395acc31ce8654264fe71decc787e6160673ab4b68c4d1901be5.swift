#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Whole finite Native child coverage with mandatory per-chart offset guards.
public struct OriginalFiniteNativeOffsetLawFamily<S:OriginalOffsetSourceReading>:Sendable where S.Child:OriginalBSplineSourceReading {
    public let source:OriginalSourceBinding<S>
    public let child:OriginalFiniteBSplineCharts<S.Child>
    public let laws:[OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>]
    public let proofDepth:ExactScalarDepth
    public var field:OriginalExactScalarDomain { child.field }
    /// Full child extent, not a Cartesian assertion about offset position support.
    public var enclosingSupport:[OriginalSourceParameterInterval<OriginalExactScalar>] { child.support }
    init(source:OriginalSourceBinding<S>,child:OriginalFiniteBSplineCharts<S.Child>,
        laws:[OriginalOffsetLawReceipt<S,OriginalBSplineChartSelection,OriginalExactScalarDomain>],proofDepth:ExactScalarDepth) {
        self.source=source;self.child=child;self.laws=laws;self.proofDepth=proofDepth
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
