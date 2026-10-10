#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retains every original child coordinate, guarded position law and owner.
public struct OriginalCurveParameterGraphEvidence<C: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E: Sendable>: Sendable {
    public let child: OriginalParametricGraphReceipt<C,F,E>
    init(child: OriginalParametricGraphReceipt<C,F,E>) { self.child=child }
}
