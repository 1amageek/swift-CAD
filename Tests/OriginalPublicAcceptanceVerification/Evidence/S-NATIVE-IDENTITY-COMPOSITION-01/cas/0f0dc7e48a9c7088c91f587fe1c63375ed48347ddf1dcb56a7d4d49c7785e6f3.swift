#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Whole original plane basis proof; coordinates and projections use this owner.
public struct OriginalPlaneBasisReceipt<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let source: OriginalSourceBinding<S>
    public let field: F
    public let origin: [F.Value]
    public let normal: [F.Value]
    public let u: [F.Value]
    public let v: [F.Value]
    init(source: OriginalSourceBinding<S>,field: F,origin: [F.Value],normal: [F.Value],u: [F.Value],v: [F.Value]) {
        self.source = source; self.field = field; self.origin = origin; self.normal = normal; self.u = u; self.v = v
    }
}
