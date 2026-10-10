#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original guarded child graph remains owned after spatial position composition.
public struct OriginalSpatialGraphEvidence<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E: Sendable>: Sendable {
    public let child: OriginalParametricGraphReceipt<S,F,E>
    init(child: OriginalParametricGraphReceipt<S,F,E>) { self.child=child }
}
