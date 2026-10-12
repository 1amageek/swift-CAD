#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original position and cell bounds share immutable coefficient owners.
public struct OriginalRetainedSurfaceCell<F:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:Sendable {
    public let homogeneous:[ExactPolynomial<F>]
    public let support:[OriginalSourceParameterInterval<F.Value>]
    init(homogeneous:[ExactPolynomial<F>],support:[OriginalSourceParameterInterval<F.Value>]) {
        self.homogeneous=homogeneous;self.support=support
    }
}
