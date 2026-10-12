#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

/// Exact correspondence from a lower projection condition to its whole-parent cut.
public struct ExactRealCellProjectionBinding<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let polynomial: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    public let normalized: ExactPolynomial<ExactAlgebraicScalarDomain<Base>>
    public let multiplier: ExactAlgebraicScalar<Base>
    public let lowerLawIndex: Int?
}
