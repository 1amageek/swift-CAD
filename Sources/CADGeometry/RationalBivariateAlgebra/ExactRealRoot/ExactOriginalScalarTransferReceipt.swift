#if ORIGINAL_COORDINATE_ISOLATED_VERIFICATION
import L0
import L2
#elseif L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retains the L2 source values and their exact original-coordinate authority.
public struct ExactOriginalScalarTransferReceipt: Sendable {
    public let sources: [ExactAlgebraicScalar<OriginalExactScalarDomain>]
    public let field: OriginalExactScalarDomain
    public let values: [OriginalExactScalar]
    init(sources: [ExactAlgebraicScalar<OriginalExactScalarDomain>],
        field: OriginalExactScalarDomain, values: [OriginalExactScalar]) {
        self.sources = sources; self.field = field; self.values = values
    }
}
