#if ORIGINAL_QUADRATIC_BOUNDARY_ISOLATED_VERIFICATION
import L0
import L1
import SourceIssuer
#endif

/// Issues the complete directed UV arc and cap of one positive clamped quadratic.
public protocol OriginalRationalQuadraticBoundaryIssuing {
    associatedtype Source: OriginalBSplineSourceReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        field: borrowing Field,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalRationalQuadraticBoundaryReceipt<Source,Field>
}
